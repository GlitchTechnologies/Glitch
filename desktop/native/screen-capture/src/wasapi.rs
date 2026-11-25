use std::{
    collections::VecDeque,
    mem::{ManuallyDrop, size_of},
    ptr::null_mut,
    slice,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{SyncSender, sync_channel},
    },
    thread,
    time::Duration,
};

use napi::{Error, bindgen_prelude::Buffer};
use napi_derive::napi;
use windows::{
    Win32::{
        Media::Audio::*,
        System::{
            Com::{
                BLOB, COINIT_MULTITHREADED, CoInitializeEx, CoTaskMemAlloc, CoUninitialize,
                StructuredStorage::*,
            },
            Variant::VT_BLOB,
        },
    },
    core::{HRESULT, Interface, Ref, implement},
};

const SAMPLE_RATE: u32 = 48_000;
const CHANNELS: u16 = 2;
const BYTES_PER_FRAME: u16 = CHANNELS * 2;
const MAX_QUEUED_FRAMES: usize = SAMPLE_RATE as usize / 10;
const POLL: Duration = Duration::from_millis(5);
static WASAPI_IN_USE: AtomicBool = AtomicBool::new(false);

struct WasapiLease;

impl WasapiLease {
    fn acquire() -> napi::Result<Self> {
        WASAPI_IN_USE
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Relaxed)
            .map_err(|_| Error::from_reason("Windows ещё завершает предыдущий захват звука"))?;
        Ok(Self)
    }
}

impl Drop for WasapiLease {
    fn drop(&mut self) {
        WASAPI_IN_USE.store(false, Ordering::Release);
    }
}

#[napi(object)]
pub struct AudioPacket {
    pub pcm: Buffer,
    pub frames: u32,
    pub timestamp: f64,
}

#[napi(object)]
pub struct AudioRead {
    pub ready: bool,
    pub sample_rate: u32,
    pub channels: u32,
    pub packets: Vec<AudioPacket>,
}

struct Packet {
    pcm: Vec<u8>,
    frames: u32,
    timestamp: u64,
}

#[derive(Default)]
struct SharedAudio {
    ready: bool,
    error: Option<String>,
    frames: usize,
    packets: VecDeque<Packet>,
}

impl SharedAudio {
    fn queue(&mut self, packet: Packet) {
        while self.frames + packet.frames as usize > MAX_QUEUED_FRAMES {
            let Some(old) = self.packets.pop_front() else { return };
            self.frames -= old.frames as usize;
        }
        self.frames += packet.frames as usize;
        self.packets.push_back(packet);
    }
}

struct ComApartment;

impl ComApartment {
    fn enter() -> windows::core::Result<Self> {
        unsafe { CoInitializeEx(None, COINIT_MULTITHREADED).ok()? };
        Ok(Self)
    }
}

impl Drop for ComApartment {
    fn drop(&mut self) {
        unsafe { CoUninitialize() };
    }
}

#[implement(IActivateAudioInterfaceCompletionHandler)]
struct Activation(SyncSender<()>);

impl IActivateAudioInterfaceCompletionHandler_Impl for Activation_Impl {
    fn ActivateCompleted(
        &self,
        _: Ref<'_, IActivateAudioInterfaceAsyncOperation>,
    ) -> windows::core::Result<()> {
        let _ = self.0.try_send(());
        Ok(())
    }
}

fn open_excluding_glitch() -> Result<IAudioClient, String> {
    let (completed, completion) = sync_channel(1);
    let handler: IActivateAudioInterfaceCompletionHandler = Activation(completed).into();
    let params = AUDIOCLIENT_ACTIVATION_PARAMS {
        ActivationType: AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,
        Anonymous: AUDIOCLIENT_ACTIVATION_PARAMS_0 {
            ProcessLoopbackParams: AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
                TargetProcessId: std::process::id(),
                ProcessLoopbackMode: PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE,
            },
        },
    };
    // PROPVARIANT владеет VT_BLOB: при удалении Windows вызывает
    // CoTaskMemFree. Выделяем блок тем же COM-аллокатором.
    let size = size_of::<AUDIOCLIENT_ACTIVATION_PARAMS>();
    let blob = unsafe { CoTaskMemAlloc(size) }.cast::<AUDIOCLIENT_ACTIVATION_PARAMS>();
    if blob.is_null() {
        return Err("Windows не выделила память для запуска захвата звука".into());
    }
    unsafe { blob.write(params) };
    let activation = PROPVARIANT {
        Anonymous: PROPVARIANT_0 {
            Anonymous: ManuallyDrop::new(PROPVARIANT_0_0 {
                vt: VT_BLOB,
                Anonymous: PROPVARIANT_0_0_0 {
                    blob: BLOB {
                        cbSize: size as u32,
                        pBlobData: blob.cast(),
                    },
                },
                ..Default::default()
            }),
        },
    };
    let operation = unsafe {
        ActivateAudioInterfaceAsync(
            VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
            &IAudioClient::IID,
            Some(&activation),
            &handler,
        )
    }
    .map_err(super::message)?;
    // Таймаут интерфейса только выставляет stop. Рабочий поток держит
    // операцию COM, обработчик и параметры до уведомления Windows.
    completion
        .recv()
        .map_err(|_| "Windows не подтвердила открытие захвата звука".to_owned())?;
    let mut result = HRESULT(0);
    let mut unknown = None;
    unsafe { operation.GetActivateResult(&mut result, &mut unknown) }.map_err(super::message)?;
    result.ok().map_err(super::message)?;
    unknown
        .ok_or("Windows не вернула звуковое устройство")?
        .cast()
        .map_err(super::message)
}

fn read_packet(capture: &IAudioCaptureClient) -> windows::core::Result<Option<Packet>> {
    let mut data = null_mut();
    let mut frames = 0;
    let mut flags = 0;
    let mut qpc_100ns = 0;
    unsafe { capture.GetBuffer(&mut data, &mut frames, &mut flags, None, Some(&mut qpc_100ns))? };
    if frames == 0 {
        return Ok(None);
    }
    let length = frames as usize * usize::from(BYTES_PER_FRAME);
    let bad_timestamp = flags & AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR.0 as u32 != 0;
    let pcm = if frames as usize > MAX_QUEUED_FRAMES || bad_timestamp {
        None
    } else if flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0 {
        Some(vec![0; length])
    } else if data.is_null() {
        None
    } else {
        // WASAPI владеет памятью до ReleaseBuffer.
        Some(unsafe { slice::from_raw_parts(data, length) }.to_vec())
    };
    unsafe { capture.ReleaseBuffer(frames)? };
    Ok(pcm.map(|pcm| Packet {
        pcm,
        frames,
        timestamp: qpc_100ns / 10,
    }))
}

fn capture_audio(shared: &Mutex<SharedAudio>, stop: &AtomicBool) -> Result<(), String> {
    let _com = ComApartment::enter().map_err(super::message)?;
    let audio = open_excluding_glitch()?;
    if stop.load(Ordering::Relaxed) {
        return Ok(());
    }
    let format = WAVEFORMATEX {
        wFormatTag: WAVE_FORMAT_PCM as u16,
        nChannels: CHANNELS,
        nSamplesPerSec: SAMPLE_RATE,
        nAvgBytesPerSec: SAMPLE_RATE * u32::from(BYTES_PER_FRAME),
        nBlockAlign: BYTES_PER_FRAME,
        wBitsPerSample: 16,
        cbSize: 0,
    };
    let capture: IAudioCaptureClient = unsafe {
        audio
            .Initialize(
                AUDCLNT_SHAREMODE_SHARED,
                AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
                0,
                0,
                &format,
                None,
            )
            .map_err(super::message)?;
        let client = audio.GetService().map_err(super::message)?;
        audio.Start().map_err(super::message)?;
        client
    };
    shared.lock().unwrap().ready = true;
    let read = || -> windows::core::Result<()> {
        while !stop.load(Ordering::Relaxed) {
            if unsafe { capture.GetNextPacketSize()? } == 0 {
                thread::sleep(POLL);
            } else if let Some(packet) = read_packet(&capture)? {
                shared.lock().unwrap().queue(packet);
            }
        }
        Ok(())
    };
    let result = read();
    let stopped = unsafe { audio.Stop() };
    result.and(stopped).map_err(super::message)
}

/// Экземпляр владеет звуком одного показа и исключает дерево процессов Glitch.
#[napi]
pub struct WasapiCapture {
    shared: Arc<Mutex<SharedAudio>>,
    stop: Arc<AtomicBool>,
}

#[napi]
impl WasapiCapture {
    #[napi(constructor)]
    pub fn new() -> napi::Result<Self> {
        let lease = WasapiLease::acquire()?;
        let shared = Arc::new(Mutex::new(SharedAudio::default()));
        let stop = Arc::new(AtomicBool::new(false));
        let worker_shared = Arc::clone(&shared);
        let worker_stop = Arc::clone(&stop);
        thread::Builder::new()
            .name("glitch-wasapi".into())
            .spawn(move || {
                let _lease = lease;
                if let Err(error) = capture_audio(&worker_shared, &worker_stop) {
                    worker_shared.lock().unwrap().error = Some(error);
                }
            })
            .map_err(|error| Error::from_reason(error.to_string()))?;
        Ok(Self { shared, stop })
    }

    #[napi]
    pub fn read(&self) -> napi::Result<AudioRead> {
        let mut shared = self.shared.lock().unwrap();
        if let Some(error) = &shared.error {
            return Err(Error::from_reason(error.clone()));
        }
        shared.frames = 0;
        Ok(AudioRead {
            ready: shared.ready,
            sample_rate: SAMPLE_RATE,
            channels: u32::from(CHANNELS),
            packets: shared
                .packets
                .drain(..)
                .map(|packet| AudioPacket {
                    pcm: packet.pcm.into(),
                    frames: packet.frames,
                    timestamp: packet.timestamp as f64,
                })
                .collect(),
        })
    }

    #[napi]
    pub fn stop(&self) {
        self.stop.store(true, Ordering::Relaxed);
    }
}

impl Drop for WasapiCapture {
    fn drop(&mut self) {
        self.stop();
    }
}
