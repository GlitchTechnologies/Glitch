use std::{
    collections::HashMap,
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration, Instant},
};

use napi::{Error, bindgen_prelude::Buffer};
use napi_derive::napi;
use windows::{
    Win32::Graphics::{
        Direct3D11::*,
        Dxgi::{
            DXGI_SHARED_RESOURCE_READ, DXGI_SHARED_RESOURCE_WRITE, IDXGIResource1,
        },
    },
    Win32::System::Performance::QueryPerformanceFrequency,
    core::{HRESULT, Interface},
};
#[cfg(feature = "capture-probe")]
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_NV12;
use windows_capture::{
    dxgi_duplication_api::{DxgiDuplicationApi, DxgiDuplicationFormat, Error as DxgiError},
    monitor::Monitor,
};
#[cfg(feature = "capture-probe")]
use windows_capture::{
    capture::{CaptureControl, Context, GraphicsCaptureApiHandler},
    frame::Frame,
    graphics_capture_api::InternalCaptureControl,
    settings::*,
};

#[cfg(feature = "capture-probe")]
mod nv12;
#[cfg(feature = "capture-probe")]
mod probe_etw;
#[cfg(feature = "capture-probe")]
mod probe_timing;
mod wasapi;
#[cfg(feature = "capture-probe")]
use nv12::{Nv12Converter, Nv12Target};

const DEFAULT_SLOTS: usize = 4;
const MAX_FPS: u32 = 60;
const GPU_TIMEOUT: Duration = Duration::from_millis(250);
const DXGI_RECOVERY_TIMEOUT: Duration = Duration::from_secs(3);
const DXGI_RECOVERY_INTERVAL: Duration = Duration::from_millis(100);

#[napi]
pub fn capture_api_version() -> u32 {
    5
}

struct Slot {
    texture: ID3D11Texture2D,
    handle: OwnedHandle,
    #[cfg(feature = "capture-probe")]
    nv12: Option<Nv12Target>,
}

impl Slot {
    fn new(
        device: &ID3D11Device,
        source_desc: &D3D11_TEXTURE2D_DESC,
        #[cfg(feature = "capture-probe")] converter: Option<&Nv12Converter>,
    ) -> windows::core::Result<Self> {
        #[cfg(feature = "capture-probe")]
        let (format, sharing) = if converter.is_some() {
            (DXGI_FORMAT_NV12, D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX)
        } else {
            (source_desc.Format, D3D11_RESOURCE_MISC_SHARED)
        };
        #[cfg(not(feature = "capture-probe"))]
        let (format, sharing) = (source_desc.Format, D3D11_RESOURCE_MISC_SHARED);
        let desc = D3D11_TEXTURE2D_DESC {
            Usage: D3D11_USAGE_DEFAULT,
            BindFlags: (D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE).0 as u32,
            CPUAccessFlags: 0,
            Format: format,
            MiscFlags: (D3D11_RESOURCE_MISC_SHARED_NTHANDLE | sharing).0 as u32,
            ..*source_desc
        };
        let mut texture = None;
        // D3D11 получает дескриптор поверхности и возвращает отдельную GPU-текстуру.
        unsafe { device.CreateTexture2D(&desc, None, Some(&mut texture))? };
        let texture = texture.ok_or_else(windows::core::Error::empty)?;
        #[cfg(feature = "capture-probe")]
        let nv12 = converter
            .map(|converter| converter.target(&texture))
            .transpose()?;
        let resource = texture.cast::<IDXGIResource1>()?;
        let access = DXGI_SHARED_RESOURCE_READ.0 | DXGI_SHARED_RESOURCE_WRITE.0;
        let handle = unsafe { resource.CreateSharedHandle(None, access, None)? };
        let handle = unsafe { OwnedHandle::from_raw_handle(handle.0) };
        Ok(Self {
            texture,
            handle,
            #[cfg(feature = "capture-probe")]
            nv12,
        })
    }
}

#[napi(object)]
#[derive(Clone, Default)]
pub struct GpuStageTotals {
    pub acquire_texture: f64,
    pub prepare_texture: f64,
    pub video_processor_blt: f64,
    pub submit_commands: f64,
    pub wait_for_gpu: f64,
    pub release_texture: f64,
}

#[napi(object)]
#[derive(Clone)]
pub struct ProbeSeries {
    pub metric: String,
    pub samples: Vec<f64>,
}

#[napi(object)]
pub struct ProbeGpuConfig {
    pub priority: i32,
    pub trace_queue: bool,
}

#[napi(object)]
#[derive(Clone, Default)]
pub struct CaptureStats {
    pub frames: u32,
    pub paced_out: u32,
    pub no_slot: u32,
    pub replaced: u32,
    pub copied: u32,
    pub copy_wait_ms: f64,
    pub max_copy_wait_ms: f64,
    pub max_frame_gap_ms: f64,
    pub gpu_stage_ms: GpuStageTotals,
    pub probe_timings: Option<Vec<ProbeSeries>>,
    pub probe_gpu_priority: Option<i32>,
    pub probe_queue_marked_copies: Option<u32>,
}

struct Captured {
    slot: Arc<Slot>,
    width: u32,
    height: u32,
    timestamp: i64,
    capture_timestamp: i64,
    #[cfg(feature = "capture-probe")]
    ready_at: Instant,
}

#[derive(Default)]
struct Shared {
    pending: Option<Captured>,
    stats: CaptureStats,
    error: Option<String>,
    recoveries: u32,
    #[cfg(feature = "capture-probe")]
    probe_samples: Option<probe_timing::Samples>,
}

struct FrameExporter {
    shared: Arc<Mutex<Shared>>,
    slots: Vec<Arc<Slot>>,
    slot_limit: usize,
    query: ID3D11Query,
    dimensions: Option<(u32, u32)>,
    first_timestamp: Option<i64>,
    last_timestamp: Option<i64>,
    next_timestamp: i64,
    frame_period_us: i64,
    #[cfg(feature = "capture-probe")]
    converter: Option<Nv12Converter>,
    #[cfg(feature = "capture-probe")]
    copy_probe: Option<probe_timing::CopyProbe>,
    #[cfg(feature = "capture-probe")]
    queue_markers: Option<probe_etw::QueueMarkers>,
}

impl FrameExporter {
    fn new(
        device: &ID3D11Device,
        shared: Arc<Mutex<Shared>>,
        slot_limit: usize,
        fps: u32,
    ) -> Result<Self, String> {
        let desc = D3D11_QUERY_DESC {
            Query: D3D11_QUERY_EVENT,
            MiscFlags: 0,
        };
        let mut query = None;
        unsafe {
            device
                .CreateQuery(&desc, Some(&mut query))
                .map_err(message)?
        };
        Ok(Self {
            shared,
            slots: Vec::with_capacity(slot_limit),
            slot_limit,
            query: query.ok_or("D3D11 не создал запрос завершения")?,
            dimensions: None,
            first_timestamp: None,
            last_timestamp: None,
            next_timestamp: 0,
            frame_period_us: 1_000_000 / i64::from(fps),
            #[cfg(feature = "capture-probe")]
            converter: None,
            #[cfg(feature = "capture-probe")]
            copy_probe: None,
            #[cfg(feature = "capture-probe")]
            queue_markers: None,
        })
    }

    fn capture(
        &mut self,
        device: &ID3D11Device,
        context: &ID3D11DeviceContext,
        texture: &ID3D11Texture2D,
        desc: &D3D11_TEXTURE2D_DESC,
        timestamp: i64,
    ) -> Result<(), String> {
        {
            let mut shared = self.shared.lock().unwrap();
            shared.stats.frames += 1;
            if let Some(last) = self.last_timestamp {
                let gap = (timestamp - last) as f64 / 1000.0;
                shared.stats.max_frame_gap_ms = shared.stats.max_frame_gap_ms.max(gap);
                #[cfg(feature = "capture-probe")]
                if let Some(samples) = &mut shared.probe_samples {
                    samples.add("dxgiPresentGapMs", gap);
                }
            }
            self.last_timestamp = Some(timestamp);
            if timestamp < self.next_timestamp {
                shared.stats.paced_out += 1;
                return Ok(());
            }
            self.next_timestamp = (self.next_timestamp + self.frame_period_us).max(timestamp);
        }

        let dimensions = (desc.Width, desc.Height);
        match self.dimensions {
            Some(previous) if previous != dimensions => {
                return Err("Разрешение монитора изменилось во время захвата".into());
            }
            None => self.dimensions = Some(dimensions),
            _ => {}
        }
        let slot = match self.slots.iter().find(|slot| Arc::strong_count(slot) == 1) {
            Some(slot) => slot,
            None if self.slots.len() < self.slot_limit => {
                self.slots.push(Arc::new(
                    Slot::new(
                        device,
                        desc,
                        #[cfg(feature = "capture-probe")]
                        self.converter.as_ref(),
                    )
                    .map_err(message)?,
                ));
                self.slots.last().unwrap()
            }
            None => {
                self.shared.lock().unwrap().stats.no_slot += 1;
                return Ok(());
            }
        };

        let start = Instant::now();
        #[cfg(feature = "capture-probe")]
        let nv12_lock = slot
            .nv12
            .as_ref()
            .map(Nv12Target::lock)
            .transpose()
            .map_err(message)?;
        let acquired_at = Instant::now();
        #[cfg(feature = "capture-probe")]
        let copy_called_at = self.copy_probe.as_ref().map(|probe| {
            probe.begin(context);
            Instant::now()
        });
        #[cfg(feature = "capture-probe")]
        let mut marked = self.mark_queue(probe_etw::CopyEvent::CopyCall);
        #[cfg(feature = "capture-probe")]
        let blt_time = if let Some(target) = &slot.nv12 {
            self.converter
                .as_mut()
                .unwrap()
                .convert(device, context, texture, desc, target)
                .map_err(message)?
        } else {
            unsafe { context.CopyResource(&slot.texture, texture) };
            Duration::ZERO
        };
        #[cfg(not(feature = "capture-probe"))]
        unsafe {
            context.CopyResource(&slot.texture, texture);
        }
        #[cfg(not(feature = "capture-probe"))]
        let blt_time = Duration::ZERO;
        let prepared_at = Instant::now();
        #[cfg(feature = "capture-probe")]
        let use_fence = self.copy_probe.as_mut().is_some_and(|probe| probe.end(context));
        #[cfg(not(feature = "capture-probe"))]
        let use_fence = false;
        #[cfg(feature = "capture-probe")]
        {
            marked &= self.mark_queue(probe_etw::CopyEvent::FlushCall);
        }
        // Подтверждение готовности нужно до передачи пикселей другому D3D11-девайсу.
        unsafe {
            if !use_fence {
                context.End(&self.query);
            }
            context.Flush();
        }
        let submitted_at = Instant::now();
        #[cfg(feature = "capture-probe")]
        {
            marked &= self.mark_queue(probe_etw::CopyEvent::FlushReturned);
        }
        #[cfg(feature = "capture-probe")]
        let measuring = self.copy_probe.is_some();
        #[cfg(feature = "capture-probe")]
        let (mut polls, mut poll_time, mut sleep_time, mut longest_sleep) =
            (0, Duration::ZERO, Duration::ZERO, Duration::ZERO);
        #[cfg(feature = "capture-probe")]
        if let Some(probe) = self.copy_probe.as_ref().filter(|_| use_fence) {
            probe.wait(start)?;
        }
        while !use_fence {
            #[cfg(feature = "capture-probe")]
            let poll_started = measuring.then(Instant::now);
            let hr = unsafe {
                (Interface::vtable(context).GetData)(
                    Interface::as_raw(context),
                    Interface::as_raw(&self.query),
                    std::ptr::null_mut(),
                    0,
                    D3D11_ASYNC_GETDATA_DONOTFLUSH.0 as u32,
                )
            };
            #[cfg(feature = "capture-probe")]
            if let Some(poll_started) = poll_started {
                polls += 1;
                poll_time += poll_started.elapsed();
            }
            match hr {
                HRESULT(0) => break,
                HRESULT(1) if start.elapsed() < GPU_TIMEOUT => {
                    #[cfg(feature = "capture-probe")]
                    let sleep_started = measuring.then(Instant::now);
                    thread::sleep(Duration::from_micros(250));
                    #[cfg(feature = "capture-probe")]
                    if let Some(sleep_started) = sleep_started {
                        let slept = sleep_started.elapsed();
                        sleep_time += slept;
                        longest_sleep = longest_sleep.max(slept);
                    }
                }
                HRESULT(1) => return Err("D3D11 не завершил подготовку текстуры за 250 мс".into()),
                error => return Err(message(windows::core::Error::from_hresult(error))),
            }
        }
        let gpu_done_at = Instant::now();
        #[cfg(feature = "capture-probe")]
        {
            marked &= self.mark_queue(probe_etw::CopyEvent::ReadyObserved);
        }
        #[cfg(feature = "capture-probe")]
        let gpu_copy_ms = self.copy_probe.as_ref().and_then(|probe| probe.copy_ms(context));
        #[cfg(feature = "capture-probe")]
        if let Some(lock) = nv12_lock {
            lock.release().map_err(message)?;
        }
        let released_at = Instant::now();
        let ms = |from: Instant, until: Instant| (until - from).as_secs_f64() * 1000.0;
        let elapsed = ms(start, released_at);
        let mut shared = self.shared.lock().unwrap();
        #[cfg(feature = "capture-probe")]
        if marked {
            if let Some(count) = &mut shared.stats.probe_queue_marked_copies {
                *count += 1;
            }
        }
        #[cfg(feature = "capture-probe")]
        if let (Some(samples), Some(copy_called_at)) = (&mut shared.probe_samples, copy_called_at) {
            samples.add("copyCallCpuMs", ms(copy_called_at, prepared_at));
            samples.add("submitAndFlushCpuMs", ms(prepared_at, submitted_at));
            let wait = ms(submitted_at, gpu_done_at);
            samples.add(if use_fence { "fenceWaitMs" } else { "pollWaitMs" }, wait);
            samples.add(if use_fence { "fenceCopyToReadyMs" } else { "pollCopyToReadyMs" },
                ms(copy_called_at, gpu_done_at));
            if let Some(gpu_copy_ms) = gpu_copy_ms {
                samples.add(if use_fence { "fenceGpuCopyMs" } else { "pollGpuCopyMs" }, gpu_copy_ms);
                samples.add(if use_fence { "fenceOtherWaitMs" } else { "pollOtherWaitMs" },
                    (ms(copy_called_at, gpu_done_at) - gpu_copy_ms).max(0.0));
            }
            if !use_fence {
                samples.add("pollCalls", polls as f64);
                samples.add("pollGetDataCpuMs", poll_time.as_secs_f64() * 1000.0);
                samples.add("pollSleepTotalMs", sleep_time.as_secs_f64() * 1000.0);
                samples.add("pollSleepOvershootMs",
                    sleep_time.saturating_sub(Duration::from_micros(250 * (polls - 1))).as_secs_f64() * 1000.0);
                samples.add("pollLongestSleepMs", longest_sleep.as_secs_f64() * 1000.0);
            }
        }
        shared.stats.copied += 1;
        shared.stats.copy_wait_ms += elapsed;
        shared.stats.max_copy_wait_ms = shared.stats.max_copy_wait_ms.max(elapsed);
        let stages = &mut shared.stats.gpu_stage_ms;
        stages.acquire_texture += ms(start, acquired_at);
        stages.prepare_texture += ((prepared_at - acquired_at) - blt_time).as_secs_f64() * 1000.0;
        stages.video_processor_blt += blt_time.as_secs_f64() * 1000.0;
        stages.submit_commands += ms(prepared_at, submitted_at);
        stages.wait_for_gpu += ms(submitted_at, gpu_done_at);
        stages.release_texture += ms(gpu_done_at, released_at);
        let previous = shared.pending.replace(Captured {
            slot: Arc::clone(slot),
            width: dimensions.0,
            height: dimensions.1,
            timestamp: timestamp - *self.first_timestamp.get_or_insert(timestamp),
            capture_timestamp: timestamp,
            #[cfg(feature = "capture-probe")]
            ready_at: Instant::now(),
        });
        shared.stats.replaced += u32::from(previous.is_some());
        Ok(())
    }

    #[cfg(feature = "capture-probe")]
    fn mark_queue(&self, event: probe_etw::CopyEvent) -> bool {
        self.queue_markers.as_ref().is_some_and(|markers| markers.write(event))
    }
}

fn message(error: windows::core::Error) -> String {
    error.to_string()
}

#[cfg(feature = "capture-probe")]
struct WgcHandler(FrameExporter);

#[cfg(feature = "capture-probe")]
impl GraphicsCaptureApiHandler for WgcHandler {
    type Flags = Arc<Mutex<Shared>>;
    type Error = String;

    fn new(ctx: Context<Self::Flags>) -> Result<Self, Self::Error> {
        Ok(Self(FrameExporter::new(
            &ctx.device,
            ctx.flags,
            DEFAULT_SLOTS,
            MAX_FPS,
        )?))
    }

    fn on_frame_arrived(
        &mut self,
        frame: &mut Frame<'_>,
        control: InternalCaptureControl,
    ) -> Result<(), Self::Error> {
        // WGC возвращает метку в 100 нс, Electron принимает микросекунды.
        let result = frame.timestamp().map_err(message).and_then(|time| {
            self.0.capture(
                frame.device(),
                frame.device_context(),
                frame.as_raw_texture(),
                frame.desc(),
                time.Duration / 10,
            )
        });
        if let Err(error) = result {
            self.0.shared.lock().unwrap().error = Some(error);
            control.stop();
        }
        Ok(())
    }

    fn on_closed(&mut self) -> Result<(), Self::Error> {
        self.0.shared.lock().unwrap().error = Some("Windows закрыл источник захвата".into());
        Ok(())
    }
}

fn capture_dxgi(
    shared: Arc<Mutex<Shared>>,
    stop: &AtomicBool,
    #[cfg(feature = "capture-probe")] nv12: bool,
    #[cfg(feature = "capture-probe")] probe_timing: bool,
    #[cfg(feature = "capture-probe")] probe_gpu: Option<ProbeGpuConfig>,
    slot_limit: usize,
    fps: u32,
    single_monitor: bool,
) -> Result<(), String> {
    let monitor = if single_monitor {
        let monitors = Monitor::enumerate().map_err(|error| error.to_string())?;
        let [monitor] = monitors.as_slice() else {
            return Err("Для этого режима DXGI должен быть подключён один монитор".into());
        };
        *monitor
    } else {
        Monitor::primary().map_err(|error| error.to_string())?
    };
    let mut qpc_frequency = 0;
    unsafe { QueryPerformanceFrequency(&mut qpc_frequency).map_err(message)? };
    let mut recovery_deadline = None;
    let mut recovery_reason = String::new();
    let mut first_timestamp = None;
    let mut last_timestamp = None;
    while !stop.load(Ordering::Relaxed) {
        if let Some(deadline) = recovery_deadline {
            if Instant::now() >= deadline {
                return Err(format!(
                    "DXGI не восстановил захват того же монитора: {recovery_reason}"
                ));
            }
        }
        let mut duplication =
            match DxgiDuplicationApi::new_options(monitor, &[DxgiDuplicationFormat::Bgra8]) {
                Ok(duplication) => duplication,
                Err(error) if recovery_deadline.is_some() => {
                    recovery_reason = error.to_string();
                    thread::sleep(DXGI_RECOVERY_INTERVAL);
                    continue;
                }
                Err(error) => return Err(error.to_string()),
            };
        let mut exporter =
            FrameExporter::new(duplication.device(), Arc::clone(&shared), slot_limit, fps)?;
        exporter.first_timestamp = first_timestamp;
        exporter.last_timestamp = last_timestamp;
        #[cfg(feature = "capture-probe")]
        if probe_timing {
            exporter.copy_probe = Some(probe_timing::CopyProbe::new(
                duplication.device(), duplication.device_context(),
            ));
        }
        #[cfg(feature = "capture-probe")]
        if let Some(config) = &probe_gpu {
            use windows::Win32::Graphics::Dxgi::IDXGIDevice;
            let device: IDXGIDevice = duplication.device().cast().map_err(message)?;
            let actual = unsafe {
                device.SetGPUThreadPriority(config.priority)
                    .and_then(|()| device.GetGPUThreadPriority())
            }.map_err(|error| format!("Не удалось выставить приоритет GPU {}: {error}", config.priority))?;
            if actual != config.priority {
                return Err(format!("Запрошен приоритет GPU {}, DXGI вернул {actual}", config.priority));
            }
            shared.lock().unwrap().stats.probe_gpu_priority = Some(actual);
            if config.trace_queue {
                exporter.queue_markers = Some(probe_etw::QueueMarkers::new()?);
            }
        }
        #[cfg(feature = "capture-probe")]
        if nv12 {
            let (width, height) = (duplication.width(), duplication.height());
            if width == 0 || height == 0 || width % 2 != 0 || height % 2 != 0 {
                return Err("Для NV12 нужны чётные ширина и высота монитора".into());
            }
            exporter.converter = Some(
                Nv12Converter::new(
                    duplication.device(),
                    duplication.device_context(),
                    width,
                    height,
                )
                .map_err(|error| format!("Инициализация видеопроцессора D3D11: {error}"))?,
            );
        }

        recovery_reason = loop {
            if stop.load(Ordering::Relaxed) {
                return Ok(());
            }
            if recovery_deadline.is_some_and(|deadline| Instant::now() >= deadline) {
                return Err(format!(
                    "DXGI не получил кадр после смены режима: {recovery_reason}"
                ));
            }
            #[cfg(feature = "capture-probe")]
            let acquire_started = probe_timing.then(Instant::now);
            let frame = match duplication.acquire_next_frame(50) {
                Ok(frame) => frame,
                Err(DxgiError::Timeout) => {
                    #[cfg(feature = "capture-probe")]
                    if let Some(started) = acquire_started {
                        if let Some(samples) = &mut shared.lock().unwrap().probe_samples {
                            samples.add("dxgiAcquireTimeoutMs", started.elapsed().as_secs_f64() * 1000.0);
                        }
                    }
                    continue;
                }
                Err(DxgiError::AccessLost) => break "DXGI потерял доступ при смене режима".into(),
                Err(error) => return Err(error.to_string()),
            };
            let ticks = frame.frame_info().LastPresentTime;
            #[cfg(feature = "capture-probe")]
            if let Some(started) = acquire_started {
                let acquire_ms = started.elapsed().as_secs_f64() * 1000.0;
                let mut acquired_qpc = 0;
                let have_qpc = ticks != 0 && unsafe {
                    windows::Win32::System::Performance::QueryPerformanceCounter(&mut acquired_qpc).is_ok()
                };
                if let Some(samples) = &mut shared.lock().unwrap().probe_samples {
                    samples.add(if ticks == 0 { "dxgiCursorOnlyMs" } else { "dxgiAcquireImageMs" }, acquire_ms);
                    if ticks != 0 {
                        samples.add("dxgiAccumulatedFrames", f64::from(frame.frame_info().AccumulatedFrames));
                    }
                    if have_qpc {
                        samples.add("presentToAcquireMs", (acquired_qpc - ticks) as f64 * 1000.0 / qpc_frequency as f64);
                    }
                }
            }
            if ticks == 0 {
                continue;
            }
            let desc = frame.texture_desc();
            if exporter.dimensions.is_some_and(|size| size != (desc.Width, desc.Height)) {
                break "Размер кадра изменился во время захвата".into();
            }
            let timestamp = (i128::from(ticks) * 1_000_000 / i128::from(qpc_frequency)) as i64;
            if exporter.last_timestamp.is_some_and(|last| timestamp <= last) {
                continue;
            }
            if recovery_deadline.take().is_some() {
                shared.lock().unwrap().recoveries += 1;
            }
            exporter.capture(
                frame.device(), frame.device_context(), frame.texture(), desc, timestamp,
            )?;
        };
        recovery_deadline.get_or_insert_with(|| Instant::now() + DXGI_RECOVERY_TIMEOUT);
        first_timestamp = exporter.first_timestamp;
        last_timestamp = exporter.last_timestamp;
        shared.lock().unwrap().pending = None;
        drop(exporter);
        drop(duplication);
        thread::sleep(DXGI_RECOVERY_INTERVAL);
    }
    Ok(())
}

enum CaptureWorker {
    #[cfg(feature = "capture-probe")]
    Wgc(CaptureControl<WgcHandler, String>),
    Dxgi {
        stop: Arc<AtomicBool>,
        thread: thread::JoinHandle<()>,
    },
}

impl CaptureWorker {
    fn is_finished(&self) -> bool {
        match self {
            #[cfg(feature = "capture-probe")]
            Self::Wgc(control) => control.is_finished(),
            Self::Dxgi { thread, .. } => thread.is_finished(),
        }
    }

    fn stop(self) -> napi::Result<()> {
        match self {
            #[cfg(feature = "capture-probe")]
            Self::Wgc(control) => control
                .stop()
                .map_err(|err| Error::from_reason(err.to_string())),
            Self::Dxgi { stop, thread } => {
                stop.store(true, Ordering::Relaxed);
                thread
                    .join()
                    .map_err(|_| Error::from_reason("Поток DXGI завершился с ошибкой"))
            }
        }
    }
}

#[napi(object)]
pub struct TextureFrame {
    pub id: u32,
    pub width: u32,
    pub height: u32,
    pub timestamp: f64,
    pub capture_timestamp: f64,
    pub recoveries: u32,
    pub handle: Buffer,
    pub pixel_format: String,
}

#[napi]
pub struct MonitorCapture {
    control: Option<CaptureWorker>,
    shared: Arc<Mutex<Shared>>,
    leased: HashMap<u32, Arc<Slot>>,
    next_id: u32,
}

#[napi]
impl MonitorCapture {
    #[napi(constructor)]
    pub fn new(
        mode: String,
        slots: Option<u32>,
        fps: Option<u32>,
        single_monitor: Option<bool>,
        probe_timing: Option<bool>,
        probe_gpu: Option<ProbeGpuConfig>,
    ) -> napi::Result<Self> {
        let fps = fps.unwrap_or(MAX_FPS);
        if !(1..=MAX_FPS).contains(&fps) {
            return Err(Error::from_reason("Частота захвата должна быть от 1 до 60 FPS"));
        }
        let single_monitor = single_monitor.unwrap_or(false);
        let supports_mode = mode == "dxgi" ||
            (cfg!(feature = "capture-probe") && matches!(mode.as_str(), "wgc" | "dxgi-nv12"));
        if !supports_mode {
            return Err(Error::from_reason("Этот режим захвата отсутствует в сборке модуля"));
        }
        if mode == "wgc" && (fps != MAX_FPS || single_monitor) {
            return Err(Error::from_reason("Эти настройки захвата поддерживает только DXGI"));
        }
        let slot_limit = slots.map_or(DEFAULT_SLOTS, |count| count as usize);
        if slot_limit != DEFAULT_SLOTS &&
            !(cfg!(feature = "capture-probe") && slot_limit == 6 && mode == "dxgi")
        {
            return Err(Error::from_reason(
                "Для DXGI BGRA допустимы 4 или 6 буферов",
            ));
        }
        let probe_timing = probe_timing.unwrap_or(false);
        if probe_timing && (!cfg!(feature = "capture-probe") || mode != "dxgi") {
            return Err(Error::from_reason("Подробные замеры доступны в стенде DXGI BGRA"));
        }
        if let Some(config) = &probe_gpu {
            if !probe_timing || !(0..=1).contains(&config.priority) || (config.trace_queue && config.priority != 0) {
                return Err(Error::from_reason("Для замеров допустимы приоритеты GPU 0 и 1, для трассы — 0"));
            }
        }
        let shared = Arc::new(Mutex::new(Shared {
            #[cfg(feature = "capture-probe")]
            probe_samples: probe_timing.then(probe_timing::Samples::default),
            stats: CaptureStats {
                probe_queue_marked_copies: probe_gpu.as_ref().filter(|config| config.trace_queue).map(|_| 0),
                ..CaptureStats::default()
            },
            ..Shared::default()
        }));
        let control = match mode.as_str() {
            #[cfg(feature = "capture-probe")]
            "wgc" => {
                let monitor =
                    Monitor::primary().map_err(|err| Error::from_reason(err.to_string()))?;
                let settings = Settings::new(
                    monitor,
                    CursorCaptureSettings::Default,
                    DrawBorderSettings::Default,
                    SecondaryWindowSettings::Default,
                    MinimumUpdateIntervalSettings::Default,
                    DirtyRegionSettings::Default,
                    ColorFormat::Bgra8,
                    Arc::clone(&shared),
                );
                let control = WgcHandler::start_free_threaded(settings)
                    .map_err(|err| Error::from_reason(err.to_string()))?;
                CaptureWorker::Wgc(control)
            }
            _ => {
                #[cfg(feature = "capture-probe")]
                let nv12 = mode == "dxgi-nv12";
                let stop = Arc::new(AtomicBool::new(false));
                let stop_signal = Arc::clone(&stop);
                let worker_shared = Arc::clone(&shared);
                let thread = thread::Builder::new()
                    .name("glitch-dxgi-capture".into())
                    .spawn(move || {
                        if let Err(error) = capture_dxgi(
                            Arc::clone(&worker_shared),
                            &stop_signal,
                            #[cfg(feature = "capture-probe")]
                            nv12,
                            #[cfg(feature = "capture-probe")]
                            probe_timing,
                            #[cfg(feature = "capture-probe")]
                            probe_gpu,
                            slot_limit,
                            fps,
                            single_monitor,
                        ) {
                            worker_shared.lock().unwrap().error = Some(error);
                        }
                    })
                    .map_err(|err| Error::from_reason(err.to_string()))?;
                CaptureWorker::Dxgi { stop, thread }
            }
        };
        Ok(Self {
            control: Some(control),
            shared,
            leased: HashMap::new(),
            next_id: 0,
        })
    }

    #[napi]
    pub fn take_frame(&mut self) -> napi::Result<Option<TextureFrame>> {
        let mut shared = self
            .shared
            .lock()
            .map_err(|_| Error::from_reason("Поток захвата Windows повредил состояние"))?;
        if let Some(error) = &shared.error {
            return Err(Error::from_reason(error.clone()));
        }
        if self
            .control
            .as_ref()
            .is_some_and(CaptureWorker::is_finished)
        {
            return Err(Error::from_reason("Поток захвата Windows завершился"));
        }
        let Some(frame) = shared.pending.take() else {
            return Ok(None);
        };
        #[cfg(feature = "capture-probe")]
        if let Some(samples) = &mut shared.probe_samples {
            samples.add("readyToTakeMs", frame.ready_at.elapsed().as_secs_f64() * 1000.0);
        }
        self.next_id += 1;
        let id = self.next_id;
        let handle = (frame.slot.handle.as_raw_handle() as usize)
            .to_le_bytes()
            .to_vec();
        #[cfg(feature = "capture-probe")]
        let pixel_format = if frame.slot.nv12.is_some() {
            "nv12"
        } else {
            "bgra"
        };
        #[cfg(not(feature = "capture-probe"))]
        let pixel_format = "bgra";
        self.leased.insert(id, frame.slot);
        Ok(Some(TextureFrame {
            id,
            width: frame.width,
            height: frame.height,
            timestamp: frame.timestamp as f64,
            capture_timestamp: frame.capture_timestamp as f64,
            recoveries: shared.recoveries,
            handle: handle.into(),
            pixel_format: pixel_format.into(),
        }))
    }

    #[napi]
    pub fn stats(&self, reset_max: bool) -> napi::Result<CaptureStats> {
        let mut shared = self
            .shared
            .lock()
            .map_err(|_| Error::from_reason("Поток захвата Windows повредил состояние"))?;
        #[cfg(feature = "capture-probe")]
        let probe_timings = shared.probe_samples.as_mut().map(|samples| {
            if reset_max {
                *samples = probe_timing::Samples::default();
            }
            samples.snapshot()
        });
        #[cfg(not(feature = "capture-probe"))]
        let probe_timings = None;
        let stats = CaptureStats { probe_timings, ..shared.stats.clone() };
        if reset_max {
            shared.stats.max_copy_wait_ms = 0.0;
            shared.stats.max_frame_gap_ms = 0.0;
        }
        Ok(stats)
    }

    #[napi]
    pub fn release_frame(&mut self, id: u32) {
        self.leased.remove(&id);
    }

    #[napi]
    pub fn request_stop(&self) {
        match &self.control {
            Some(CaptureWorker::Dxgi { stop, .. }) => stop.store(true, Ordering::Relaxed),
            _ => {}
        }
    }

    #[napi]
    pub fn is_stopped(&self) -> bool {
        self.control.as_ref().is_none_or(CaptureWorker::is_finished)
    }

    #[napi]
    pub fn stop(&mut self) -> napi::Result<()> {
        if let Some(control) = self.control.take() {
            control.stop()?;
            self.shared
                .lock()
                .map_err(|_| Error::from_reason("Поток захвата Windows повредил состояние"))?
                .pending = None;
        }
        Ok(())
    }
}

impl Drop for MonitorCapture {
    fn drop(&mut self) {
        // Сборщик мусора Electron не ждёт DXGI: у потока свои данные и D3D11.
        self.request_stop();
        #[cfg(feature = "capture-probe")]
        if matches!(&self.control, Some(CaptureWorker::Wgc(_))) {
            if let Err(error) = self.stop() {
                eprintln!("Остановка захвата Windows: {error}");
            }
        }
    }
}
