import { Component, onMount, createSignal } from 'solid-js';
import { Route, useNavigate } from '@solidjs/router';
import { AuthView } from './views/AuthView';
import { Layout } from './views/Layout';
import { WorkspaceView } from './views/WorkspaceView';
import { SettingsView } from './views/SettingsView';
import { getIdentity, setupNetworkListeners } from './tauri-bridge';
import { identity } from './store';
import { Zap } from 'lucide-solid';

/** Splash / auto-login gate: checks for existing identity before showing auth. */
const SplashGate: Component = () => {
  const navigate = useNavigate();
  const [checking, setChecking] = createSignal(true);

  onMount(async () => {
    try {
      const existing = await getIdentity();
      if (existing) {
        await setupNetworkListeners();
        navigate("/workspace", { replace: true });
      }
    } catch (e) {
      console.error("Auto-login check failed:", e);
    } finally {
      setChecking(false);
    }
  });

  return (
    <>
      {checking() ? (
        <div class="h-screen w-screen flex items-center justify-center bg-primary-50 dark:bg-[#1f1917]">
          <div class="flex flex-col items-center gap-4">
            <div class="w-16 h-16 chamfer-all chamfer-shadow flex items-center justify-center text-white animate-pulse" style="--bg-color: var(--color-primary-500); --chamfer-outer: 10px; --chamfer-inner: 8px;">
              <Zap size={32} />
            </div>
            <p class="font-black text-stone-500 text-sm tracking-wider uppercase">Loading Stoa...</p>
          </div>
        </div>
      ) : (
        <AuthView />
      )}
    </>
  );
};

const App: Component = () => {
  return (
    <>
      <Route path="/" component={SplashGate} />
      <Route path="/workspace" component={Layout}>
        <Route path="/" component={WorkspaceView} />
      </Route>
      <Route path="/settings" component={SettingsView} />
    </>
  );
};

export default App;
