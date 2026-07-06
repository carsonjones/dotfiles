<script lang="ts">
  import FloatingToolbar from '$/components/FloatingToolbar.svelte';
  import { Button } from '$/components/ui/button';
  import { Separator } from '$/components/ui/separator';
  import type { PanZoomState } from '$/util/panZoom';
  import { captureToClipboard, isClipboardAvailable } from '$/util/pngExport';
  import ArrowsToCircleIcon from '~icons/material-symbols/screenshot-frame-2';
  import PhotoCameraIcon from '~icons/material-symbols/photo-camera-outline-rounded';
  import MagnifyingGlassPlusIcon from '~icons/material-symbols/zoom-in';
  import MagnifyingGlassMinusIcon from '~icons/material-symbols/zoom-out';

  let { panZoomState }: { panZoomState: PanZoomState } = $props();
</script>

<FloatingToolbar>
  {#if isClipboardAvailable()}
    <Button
      variant="ghost"
      size="icon"
      title="Copy image (white background, 48px padding)"
      onclick={captureToClipboard}>
      <PhotoCameraIcon />
    </Button>
    <Separator orientation="vertical" />
  {/if}
  <Button variant="ghost" size="icon" title="Reset view" onclick={() => panZoomState.reset()}>
    <ArrowsToCircleIcon />
  </Button>
  <Separator orientation="vertical" />
  <Button
    variant="ghost"
    size="icon"
    class="hidden sm:block"
    onclick={() => panZoomState.zoomOut()}>
    <MagnifyingGlassMinusIcon />
  </Button>
  <Button variant="ghost" size="icon" class="hidden sm:block" onclick={() => panZoomState.zoomIn()}>
    <MagnifyingGlassPlusIcon />
  </Button>
</FloatingToolbar>
