import { Component, createSignal } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { setIdentity, setActiveLeftPane } from "../store";
import { Key, ShieldCheck, Zap } from "lucide-solid";

export const AuthView: Component = () => {
  const navigate = useNavigate();
  const [loading, setLoading] = createSignal(false);

  const generateIdentity = () => {
    setLoading(true);
    setTimeout(() => {
      setIdentity({
        name: "Crab_" + Math.floor(Math.random() * 1000),
        publicKey: "ed25519:mock_pub_key_" + Date.now()
      });
      navigate("/workspace");
      setActiveLeftPane({ type: 'dm', id: 'dm1' });
    }, 1200);
  };

  return (
    <div class="h-screen w-screen flex items-center justify-center relative bg-primary-50 dark:bg-[#1f1917] p-4">
      {/* 2D shapes for background interest */}
      <div class="absolute top-10 left-10 w-32 h-32 bg-primary-100 dark:bg-[#3d2a23] rounded-full border-2 border-stone-800 dark:border-stone-600"></div>
      <div class="absolute bottom-10 right-20 w-48 h-48 bg-accent-400/30 rounded-br-3xl rotate-12 border-2 border-stone-800 dark:border-stone-600"></div>

      <div class="relative z-10 flat-panel p-8 md:p-12 w-full max-w-md flex flex-col items-center text-center">
        <div class="w-20 h-20 chamfer-all chamfer-shadow flex items-center justify-center text-white mb-6" style="--bg-color: var(--color-primary-500); --chamfer-outer: 12px; --chamfer-inner: 10px;">
          <ShieldCheck size={40} />
        </div>
        
        <h1 class="text-4xl font-black mb-3 text-stone-900 dark:text-stone-100">
          Stoa
        </h1>
        <p class="text-stone-600 dark:text-stone-400 mb-8 font-medium">
          A secure, local-first collaboration platform. Grounded in Rust, powered by decentralized truth.
        </p>

        <div class="flex flex-col gap-4 w-full">
          <button
            class="flat-button py-4 px-6 text-lg flex items-center justify-center gap-3 w-full"
            onClick={generateIdentity}
            disabled={loading()}
          >
            {loading() ? (
              <span class="flex items-center gap-2">
                <Zap size={22} class="animate-pulse" /> Generating...
              </span>
            ) : (
              <>
                <Key size={22} />
                Generate Identity
              </>
            )}
          </button>
          
          <button class="flat-button-secondary py-3 px-6 text-sm flex items-center justify-center gap-3 w-full">
            Import Existing Key
          </button>
        </div>
      </div>
    </div>
  );
};
