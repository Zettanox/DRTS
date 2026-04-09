import { Component } from 'solid-js';
import { Route } from '@solidjs/router';
import { AuthView } from './views/AuthView';
import { Layout } from './views/Layout';
import { WorkspaceView } from './views/WorkspaceView';
import { SettingsView } from './views/SettingsView';

const App: Component = () => {
  return (
    <>
      <Route path="/" component={AuthView} />
      <Route path="/workspace" component={Layout}>
        <Route path="/" component={WorkspaceView} />
      </Route>
      <Route path="/settings" component={SettingsView} />
    </>
  );
};

export default App;
