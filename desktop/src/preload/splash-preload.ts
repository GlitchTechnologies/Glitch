import { contextBridge, ipcRenderer } from 'electron';
import type { SplashSendChannels, SplashState, SplashStateChannel } from '../shared/ipc';

const STATE: SplashStateChannel = 'splash:state';
const RETRY: keyof SplashSendChannels = 'splash:retry';

contextBridge.exposeInMainWorld('glitchSplash', {
  onState: (listener: (state: SplashState) => void) => {
    ipcRenderer.on(STATE, (_event, state: SplashState) => listener(state));
  },
  retryNow: () => ipcRenderer.send(RETRY),
});
