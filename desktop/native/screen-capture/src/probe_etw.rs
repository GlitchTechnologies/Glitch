use windows::{
    Win32::System::Diagnostics::Etw::{
        EVENT_DESCRIPTOR, EventProviderEnabled, EventRegister, EventUnregister, EventWrite, REGHANDLE,
    },
    core::GUID,
};

const PROVIDER: GUID = GUID::from_u128(0x5cb165ff_eaff_4cf8_9244_55d1adef74e5);
const LEVEL: u8 = 4;
const KEYWORD: u64 = 1;

pub(crate) enum CopyEvent {
    CopyCall = 1,
    FlushCall = 2,
    FlushReturned = 3,
    ReadyObserved = 4,
}

pub(crate) struct QueueMarkers(REGHANDLE);

impl QueueMarkers {
    pub fn new() -> Result<Self, String> {
        let mut handle = REGHANDLE::default();
        let error = unsafe { EventRegister(&PROVIDER, None, None, &mut handle) };
        if error != 0 {
            return Err(format!("Не удалось подключить метки трассы GPU, Win32 {error}"));
        }
        Ok(Self(handle))
    }

    pub fn write(&self, event: CopyEvent) -> bool {
        let descriptor = EVENT_DESCRIPTOR {
            Id: event as u16,
            Level: LEVEL,
            Keyword: KEYWORD,
            ..Default::default()
        };
        unsafe {
            EventProviderEnabled(self.0, LEVEL, KEYWORD)
                && EventWrite(self.0, &descriptor, None) == 0
        }
    }
}

impl Drop for QueueMarkers {
    fn drop(&mut self) {
        unsafe { EventUnregister(self.0) };
    }
}
