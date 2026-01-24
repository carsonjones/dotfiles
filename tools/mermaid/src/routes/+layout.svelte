<script lang="ts">
  import { Toaster } from '$/components/ui/sonner/index.js';
  import { initHandler } from '$/util/util';
  import { onMount, type Snippet } from 'svelte';
  import '../app.css';

  interface Props {
    children: Snippet;
  }

  let { children }: Props = $props();

  onMount(() => {
    window.addEventListener('hashchange', () => {
      void initHandler();
    });
  });
</script>

<Toaster />

<main class="h-dvh">
  {@render children()}
</main>
