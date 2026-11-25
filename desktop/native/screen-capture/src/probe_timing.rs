use std::{
    collections::BTreeMap,
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    time::Instant,
};

use windows::{
    Win32::{
        Foundation::{HANDLE, WAIT_OBJECT_0, WAIT_TIMEOUT},
        Graphics::Direct3D11::*,
        System::Threading::{CreateEventW, WaitForSingleObject},
    },
    core::{HRESULT, Interface, PCWSTR},
};

use super::{GPU_TIMEOUT, ProbeSeries};

const MAX_SAMPLES: usize = 8192;

#[derive(Default)]
pub(crate) struct Samples(BTreeMap<&'static str, Vec<f64>>);

impl Samples {
    pub fn add(&mut self, metric: &'static str, value: f64) {
        if value.is_finite() && value >= 0.0 {
            let samples = self.0.entry(metric).or_default();
            if samples.len() < MAX_SAMPLES {
                samples.push(value);
            }
        }
    }

    pub fn snapshot(&self) -> Vec<ProbeSeries> {
        self.0.iter().map(|(&metric, samples)| ProbeSeries {
            metric: metric.to_owned(),
            samples: samples.clone(),
        }).collect()
    }
}

pub(crate) struct CopyProbe {
    timestamps: Option<GpuTimestamps>,
    fence: Option<GpuFence>,
    use_fence: bool,
}

impl CopyProbe {
    pub fn new(device: &ID3D11Device, context: &ID3D11DeviceContext) -> Self {
        Self {
            timestamps: GpuTimestamps::new(device),
            fence: GpuFence::new(device, context),
            use_fence: false,
        }
    }

    pub fn begin(&self, context: &ID3D11DeviceContext) {
        if let Some(ts) = &self.timestamps {
            unsafe {
                context.Begin(&ts.disjoint);
                context.End(&ts.before);
            }
        }
    }

    pub fn end(&mut self, context: &ID3D11DeviceContext) -> bool {
        if let Some(ts) = &self.timestamps {
            unsafe {
                context.End(&ts.after);
                context.End(&ts.disjoint);
            }
        }
        self.use_fence = self.fence.is_some() && !self.use_fence;
        if self.use_fence && self.fence.as_mut().is_some_and(|fence| fence.arm().is_err()) {
            self.fence = None;
            self.use_fence = false;
        }
        self.use_fence
    }

    pub fn wait(&self, start: Instant) -> Result<(), String> {
        self.fence.as_ref().expect("Метод ожидания выбран только при наличии события").wait(start)
    }

    pub fn copy_ms(&self, context: &ID3D11DeviceContext) -> Option<f64> {
        self.timestamps.as_ref()?.duration_ms(context)
    }
}

struct GpuTimestamps {
    disjoint: ID3D11Query,
    before: ID3D11Query,
    after: ID3D11Query,
}

impl GpuTimestamps {
    fn new(device: &ID3D11Device) -> Option<Self> {
        let create = |kind| {
            let desc = D3D11_QUERY_DESC { Query: kind, MiscFlags: 0 };
            let mut query = None;
            unsafe { device.CreateQuery(&desc, Some(&mut query)) }.ok()?;
            query
        };
        Some(Self {
            disjoint: create(D3D11_QUERY_TIMESTAMP_DISJOINT)?,
            before: create(D3D11_QUERY_TIMESTAMP)?,
            after: create(D3D11_QUERY_TIMESTAMP)?,
        })
    }

    fn duration_ms(&self, context: &ID3D11DeviceContext) -> Option<f64> {
        let clock: D3D11_QUERY_DATA_TIMESTAMP_DISJOINT = read_query(context, &self.disjoint)?;
        if clock.Disjoint.as_bool() || clock.Frequency == 0 {
            return None;
        }
        let before: u64 = read_query(context, &self.before)?;
        let after: u64 = read_query(context, &self.after)?;
        Some(after.checked_sub(before)? as f64 * 1000.0 / clock.Frequency as f64)
    }
}

fn read_query<T: Default>(context: &ID3D11DeviceContext, query: &ID3D11Query) -> Option<T> {
    let mut data = T::default();
    let result = unsafe {
        (Interface::vtable(context).GetData)(
            Interface::as_raw(context), Interface::as_raw(query),
            std::ptr::from_mut(&mut data).cast(), size_of::<T>() as u32,
            D3D11_ASYNC_GETDATA_DONOTFLUSH.0 as u32,
        )
    };
    (result == HRESULT(0)).then_some(data)
}

struct GpuFence {
    context: ID3D11DeviceContext4,
    fence: ID3D11Fence,
    event: OwnedHandle,
    value: u64,
}

impl GpuFence {
    fn new(device: &ID3D11Device, context: &ID3D11DeviceContext) -> Option<Self> {
        let device: ID3D11Device5 = device.cast().ok()?;
        let context = context.cast().ok()?;
        let mut fence = None;
        unsafe { device.CreateFence(0, D3D11_FENCE_FLAG_NONE, &mut fence) }.ok()?;
        let fence = fence?;
        let event = unsafe { CreateEventW(None, false, false, PCWSTR::null()) }.ok()?;
        let event = unsafe { OwnedHandle::from_raw_handle(event.0) };
        Some(Self { context, fence, event, value: 0 })
    }

    fn event(&self) -> HANDLE {
        HANDLE(self.event.as_raw_handle())
    }

    fn arm(&mut self) -> windows::core::Result<()> {
        self.value += 1;
        unsafe {
            self.context.Signal(&self.fence, self.value)?;
            self.fence.SetEventOnCompletion(self.value, self.event())
        }
    }

    fn wait(&self, start: Instant) -> Result<(), String> {
        let remaining = GPU_TIMEOUT.saturating_sub(start.elapsed()).as_millis().max(1) as u32;
        match unsafe { WaitForSingleObject(self.event(), remaining) } {
            WAIT_OBJECT_0 => Ok(()),
            WAIT_TIMEOUT => Err("D3D11 не подал сигнал готовности текстуры за 250 мс".into()),
            _ => Err(windows::core::Error::from_thread().to_string()),
        }
    }
}
