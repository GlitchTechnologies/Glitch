use std::{
    mem::ManuallyDrop,
    time::{Duration, Instant},
};

use windows::{
    Win32::Graphics::{
        Direct3D11::*,
        Dxgi::{Common::*, IDXGIKeyedMutex},
    },
    core::{Error, HRESULT, Interface, Result},
};

pub(super) struct Nv12Converter {
    device: ID3D11VideoDevice,
    context: ID3D11VideoContext1,
    enumerator: ID3D11VideoProcessorEnumerator,
    processor: ID3D11VideoProcessor,
    intermediate: Option<(ID3D11Texture2D, ID3D11VideoProcessorInputView)>,
}

impl Nv12Converter {
    pub(super) fn new(
        device: &ID3D11Device,
        context: &ID3D11DeviceContext,
        width: u32,
        height: u32,
    ) -> Result<Self> {
        let device = device.cast::<ID3D11VideoDevice>()?;
        let context = context.cast::<ID3D11VideoContext1>()?;
        let rate = DXGI_RATIONAL {
            Numerator: 60,
            Denominator: 1,
        };
        let desc = D3D11_VIDEO_PROCESSOR_CONTENT_DESC {
            InputFrameFormat: D3D11_VIDEO_FRAME_FORMAT_PROGRESSIVE,
            InputFrameRate: rate,
            InputWidth: width,
            InputHeight: height,
            OutputFrameRate: rate,
            OutputWidth: width,
            OutputHeight: height,
            Usage: D3D11_VIDEO_USAGE_PLAYBACK_NORMAL,
        };
        // Метаданные текстуры в Electron должны совпадать с цветовым форматом на выходе.
        unsafe {
            let enumerator = device.CreateVideoProcessorEnumerator(&desc)?;
            let processor = device.CreateVideoProcessor(&enumerator, 0)?;
            context.VideoProcessorSetStreamAutoProcessingMode(&processor, 0, false);
            context.VideoProcessorSetStreamColorSpace1(
                &processor,
                0,
                DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709,
            );
            context.VideoProcessorSetOutputColorSpace1(
                &processor,
                DXGI_COLOR_SPACE_YCBCR_STUDIO_G22_LEFT_P709,
            );
            Ok(Self {
                device,
                context,
                enumerator,
                processor,
                intermediate: None,
            })
        }
    }

    pub(super) fn target(&self, texture: &ID3D11Texture2D) -> Result<Nv12Target> {
        let desc = D3D11_VIDEO_PROCESSOR_OUTPUT_VIEW_DESC {
            ViewDimension: D3D11_VPOV_DIMENSION_TEXTURE2D,
            ..Default::default()
        };
        let mut view = None;
        unsafe {
            self.device.CreateVideoProcessorOutputView(
                texture,
                &self.enumerator,
                &desc,
                Some(&mut view),
            )?
        };
        Ok(Nv12Target {
            view: view.ok_or_else(Error::empty)?,
            mutex: texture.cast()?,
        })
    }

    fn input_view(&self, texture: &ID3D11Texture2D) -> Result<ID3D11VideoProcessorInputView> {
        let desc = D3D11_VIDEO_PROCESSOR_INPUT_VIEW_DESC {
            ViewDimension: D3D11_VPIV_DIMENSION_TEXTURE2D,
            ..Default::default()
        };
        let mut view = None;
        unsafe {
            self.device.CreateVideoProcessorInputView(
                texture,
                &self.enumerator,
                &desc,
                Some(&mut view),
            )?
        };
        view.ok_or_else(Error::empty)
    }

    pub(super) fn convert(
        &mut self,
        device: &ID3D11Device,
        context: &ID3D11DeviceContext,
        source: &ID3D11Texture2D,
        desc: &D3D11_TEXTURE2D_DESC,
        target: &Nv12Target,
    ) -> Result<Duration> {
        // Некоторые поверхности DXGI нельзя напрямую передать видеопроцессору.
        let input = if self.intermediate.is_none() {
            match self.input_view(source) {
                Ok(view) => view,
                Err(_) => {
                    let desc = D3D11_TEXTURE2D_DESC {
                        Usage: D3D11_USAGE_DEFAULT,
                        BindFlags: 0,
                        MiscFlags: 0,
                        CPUAccessFlags: 0,
                        ..*desc
                    };
                    let mut texture = None;
                    unsafe { device.CreateTexture2D(&desc, None, Some(&mut texture))? };
                    let texture = texture.ok_or_else(Error::empty)?;
                    let view = self.input_view(&texture)?;
                    unsafe { context.CopyResource(&texture, source) };
                    self.intermediate = Some((texture, view.clone()));
                    view
                }
            }
        } else {
            let (texture, view) = self.intermediate.as_ref().unwrap();
            unsafe { context.CopyResource(texture, source) };
            view.clone()
        };
        let mut stream = D3D11_VIDEO_PROCESSOR_STREAM {
            Enable: true.into(),
            pInputSurface: ManuallyDrop::new(Some(input)),
            ..Default::default()
        };
        let started_at = Instant::now();
        let result = unsafe {
            self.context.VideoProcessorBlt(
                &self.processor,
                &target.view,
                0,
                std::slice::from_ref(&stream),
            )
        };
        let elapsed = started_at.elapsed();
        unsafe { ManuallyDrop::drop(&mut stream.pInputSurface) };
        result.map(|()| elapsed)
    }
}

pub(super) struct Nv12Target {
    view: ID3D11VideoProcessorOutputView,
    mutex: IDXGIKeyedMutex,
}

impl Nv12Target {
    pub(super) fn lock(&self) -> Result<Nv12Lock<'_>> {
        let status = unsafe { (self.mutex.vtable().AcquireSync)(self.mutex.as_raw(), 0, 50) };
        if status != HRESULT(0) {
            return Err(Error::new(
                status,
                "Не удалось получить доступ к текстуре NV12",
            ));
        }
        Ok(Nv12Lock(Some(&self.mutex)))
    }
}

pub(super) struct Nv12Lock<'a>(Option<&'a IDXGIKeyedMutex>);

impl Nv12Lock<'_> {
    pub(super) fn release(mut self) -> Result<()> {
        let mutex = self.0.take().unwrap();
        unsafe { mutex.ReleaseSync(0) }
    }
}

impl Drop for Nv12Lock<'_> {
    fn drop(&mut self) {
        if let Some(mutex) = self.0.take() {
            // При сбое кадр не попадёт к Electron, но захват нужно отпустить.
            let _ = unsafe { mutex.ReleaseSync(0) };
        }
    }
}
