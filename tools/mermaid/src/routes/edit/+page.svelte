<script lang="ts">
  import Actions from '$/components/Actions.svelte';
  import Card from '$/components/Card/Card.svelte';
  import Editor from '$/components/Editor.svelte';
  import PanZoomToolbar from '$/components/PanZoomToolbar.svelte';
  import SyncRoughToolbar from '$/components/SyncRoughToolbar.svelte';
  import { Button } from '$/components/ui/button';
  import * as Resizable from '$/components/ui/resizable';
  import View from '$/components/View.svelte';
  import type { EditorMode, Tab } from '$/types';
  import { PanZoomState } from '$/util/panZoom';
  import { updateCodeStore, validatedState } from '$/util/state.svelte';
  import { initHandler } from '$/util/util';
  import { onMount } from 'svelte';
  import CodeIcon from '~icons/custom/code';
  import LeftPanelClose from '~icons/material-symbols/left-panel-close-outline-rounded';
  import LeftPanelOpen from '~icons/material-symbols/left-panel-open-outline-rounded';
  import GearIcon from '~icons/material-symbols/settings-outline-rounded';

  const panZoomState = new PanZoomState();

  const tabSelectHandler = (tab: Tab) => {
    const editorMode: EditorMode = tab.id === 'code' ? 'code' : 'config';
    updateCodeStore({ editorMode });
  };

  const editorTabs: Tab[] = [
    {
      icon: CodeIcon,
      id: 'code',
      title: 'Code'
    },
    {
      icon: GearIcon,
      id: 'config',
      title: 'Config'
    }
  ];

  let editorPane: Resizable.Pane | undefined;
  let isEditorCollapsed = $state(false);

  onMount(async () => {
    await initHandler();
    // Allow opening straight into a collapsed-editor (diagram-only) view via
    // `/edit?collapse#...` — used by the view-clipboard command. The diagram
    // renders asynchronously, so collapse the pane then keep retrying the fit
    // across frames until the diagram is mounted and fit() actually runs.
    if (new URLSearchParams(window.location.search).has('collapse')) {
      requestAnimationFrame(() => {
        editorPane?.collapse();
        let frames = 0;
        const fitWhenReady = () => {
          // Fit once the diagram exists; do one extra pass so the final
          // collapsed width is what we center/fit against.
          if (panZoomState.fit() || frames++ > 120) {
            requestAnimationFrame(() => panZoomState.fit());
            return;
          }
          requestAnimationFrame(fitWhenReady);
        };
        fitWhenReady();
      });
    }
  });

  const toggleEditor = () => {
    if (editorPane?.isCollapsed()) {
      editorPane.expand();
    } else {
      editorPane?.collapse();
    }
  };
</script>

<div class="flex h-full flex-col overflow-hidden">
  <div class="flex flex-1 flex-col overflow-hidden pt-4">
    <Resizable.PaneGroup
      direction="horizontal"
      autoSaveId="liveEditor"
      class="gap-4 p-2 pt-0 sm:gap-0 sm:p-6 sm:pt-0">
      <Resizable.Pane
        bind:this={editorPane}
        collapsible
        collapsedSize={0}
        defaultSize={30}
        minSize={15}
        onCollapse={() => {
          isEditorCollapsed = true;
          requestAnimationFrame(() => panZoomState.fit());
        }}
        onExpand={() => {
          isEditorCollapsed = false;
          requestAnimationFrame(() => panZoomState.fit());
        }}>
        <div class="flex h-full flex-col gap-4 overflow-hidden sm:gap-6">
          <Card
            onselect={tabSelectHandler}
            isOpen
            tabs={editorTabs}
            activeTabID={validatedState.current.editorMode}
            isClosable={false}>
            {#snippet actions()}
              <Button
                variant="ghost"
                size="icon"
                onclick={toggleEditor}
                title="Hide editor"
                class="hidden size-7 [&_svg]:size-5 sm:flex">
                <LeftPanelClose />
              </Button>
            {/snippet}
            <Editor />
          </Card>

          <div class="group flex flex-wrap justify-between gap-4 sm:gap-6">
            <Actions />
          </div>
        </div>
      </Resizable.Pane>
      <Resizable.Handle class="mr-1 hidden opacity-0 sm:block" />
      <Resizable.Pane minSize={15} class="relative flex h-full flex-1 flex-col overflow-hidden">
        {#if isEditorCollapsed}
          <Button
            variant="ghost"
            size="icon"
            onclick={toggleEditor}
            title="Show editor"
            class="absolute top-1/2 left-0 z-10 hidden -translate-y-1/2 [&_svg]:size-5 sm:flex">
            <LeftPanelOpen />
          </Button>
        {/if}
        <View {panZoomState} shouldShowGrid={validatedState.current.grid} />
        <div class="absolute top-0 right-0"><PanZoomToolbar {panZoomState} /></div>
        <div class="absolute bottom-0 left-0 sm:left-5"><SyncRoughToolbar /></div>
      </Resizable.Pane>
    </Resizable.PaneGroup>
  </div>
</div>
