import { waitForRender } from '$lib/util/autoSync';
import { inputState, updateCodeStore, validatedState } from '$lib/util/state.svelte';
import { toBase64 } from 'js-base64';

export type Output = (canvas: HTMLCanvasElement) => void;

export type ImageSizeMode = 'auto' | 'width' | 'height';

export interface ExportOptions {
  /** 'auto' renders at 2x the diagram's intrinsic size; 'width'/'height' scale to `size`. */
  sizeMode?: ImageSizeMode;
  size?: number;
  /** Padding (in output pixels) added to every edge. */
  padding?: number;
  /** Canvas + SVG background. Defaults to the theme `--background`. */
  background?: string;
}

/**
 * Fix text clipping in exported SVG for hand-drawn (rough) mode.
 * svg2roughjs copies foreignObject elements but their height is often insufficient,
 * causing text bottom edges to be cut off regardless of language.
 */
const fixForeignObjectClipping = (svg: HTMLElement) => {
  const foreignObjects = svg.querySelectorAll('foreignObject');
  foreignObjects.forEach((foreignObj) => {
    const currentHeight = parseFloat(foreignObj.getAttribute('height') || '0');
    if (currentHeight <= 0) return;

    const currentY = parseFloat(foreignObj.getAttribute('y') || '0');
    const newHeight = currentHeight * 1.5;
    const heightDiff = newHeight - currentHeight;

    foreignObj.setAttribute('height', newHeight.toString());
    foreignObj.setAttribute('y', (currentY - heightDiff / 2).toString());

    // Ensure inner HTML elements are vertically centered within the expanded area
    const htmlElements = foreignObj.querySelectorAll('div, span, p');
    htmlElements.forEach((htmlEl) => {
      const el = htmlEl as HTMLElement;
      el.style.display = 'flex';
      el.style.alignItems = 'center';
      el.style.justifyContent = 'center';
      el.style.height = '100%';
    });
  });
};

const getSvgElement = () => {
  const svgElement = document.querySelector('#container svg')?.cloneNode(true) as HTMLElement;
  svgElement.setAttribute('xmlns:xlink', 'http://www.w3.org/1999/xlink');
  return svgElement;
};

export const getBase64SVG = (
  svg?: HTMLElement,
  width?: number,
  height?: number,
  background?: string
): string => {
  if (svg) {
    // Prevents the SVG size of the interface from being changed
    svg = svg.cloneNode(true) as HTMLElement;
  }
  if (height) {
    svg?.setAttribute('height', `${height}px`);
  }
  if (width) {
    svg?.setAttribute('width', `${width}px`);
  }
  // Workaround https://stackoverflow.com/questions/28690643/firefox-error-rendering-an-svg-image-to-html5-canvas-with-drawimage

  if (!svg) {
    svg = getSvgElement();
  }

  if (validatedState.current.rough) {
    fixForeignObjectClipping(svg);
  }

  svg.style.backgroundColor =
    background ?? window.getComputedStyle(document.body).getPropertyValue('--background');

  const svgString = svg.outerHTML
    .replaceAll('<br>', '<br/>')
    .replaceAll(/<img([^>]*)>/g, (m, g: string) => `<img ${g} />`);

  return toBase64(`<?xml version="1.0" encoding="UTF-8"?>
${svgString}`);
};

/**
 * Rasterize the currently-rendered diagram to a canvas and hand it to `output`.
 * Temporarily disables panZoom so the full diagram (not just the visible viewport) is captured.
 */
export const exportImage = async (
  event: Event,
  output: Output,
  { sizeMode = 'auto', size = 1080, padding = 0, background }: ExportOptions = {}
) => {
  updateCodeStore({ panZoom: false });
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await waitForRender();
  const canvas = document.createElement('canvas');
  const svg = document.querySelector<HTMLElement>('#container svg');
  if (!svg) {
    throw new Error('svg not found');
  }

  const box = svg.getBoundingClientRect();

  // In rough mode, SVG has width/height="100%" so getBoundingClientRect returns
  // the container size, not the actual diagram size. Use viewBox dimensions instead.
  const svgEl = svg as unknown as SVGSVGElement;
  const viewBox = svgEl.viewBox?.baseVal;
  const contentWidth = viewBox && viewBox.width > 0 ? viewBox.width : box.width;
  const contentHeight = viewBox && viewBox.height > 0 ? viewBox.height : box.height;

  let drawWidth: number;
  let drawHeight: number;
  if (sizeMode === 'width') {
    const ratio = contentHeight / contentWidth;
    drawWidth = size;
    drawHeight = size * ratio;
  } else if (sizeMode === 'height') {
    const ratio = contentWidth / contentHeight;
    drawWidth = size * ratio;
    drawHeight = size;
  } else {
    const multiplier = 2;
    drawWidth = contentWidth * multiplier;
    drawHeight = contentHeight * multiplier;
  }

  canvas.width = drawWidth + padding * 2;
  canvas.height = drawHeight + padding * 2;

  const context = canvas.getContext('2d');
  if (!context) {
    throw new Error('context not found');
  }

  context.fillStyle =
    background ?? window.getComputedStyle(document.body).getPropertyValue('--background');
  context.fillRect(0, 0, canvas.width, canvas.height);

  await new Promise<void>((resolve, reject) => {
    const image = new Image();
    image.addEventListener('load', () => {
      context.drawImage(image, padding, padding, drawWidth, drawHeight);
      output(canvas);
      updateCodeStore({ panZoom: true });
      resolve();
    });
    image.addEventListener('error', () => reject(new Error('image load failed')));
    image.src = `data:image/svg+xml;base64,${getBase64SVG(svg, drawWidth, drawHeight, background)}`;
    // Fallback to set panZoom to true after 2 seconds
    // This is a workaround for the case when the image is not loaded
    setTimeout(() => {
      if (!inputState.panZoom) {
        updateCodeStore({ panZoom: true });
      }
    }, 2000);
  });

  event.stopPropagation();
  event.preventDefault();
};

const isClipboardAvailable = (): boolean => {
  return Object.prototype.hasOwnProperty.call(window, 'ClipboardItem');
};

export { isClipboardAvailable };

export const clipboardCopy: Output = (canvas) => {
  canvas.toBlob((blob) => {
    try {
      if (!blob) {
        throw new Error('blob is empty');
      }
      void navigator.clipboard.write([
        new ClipboardItem({
          [blob.type]: blob
        })
      ]);
    } catch (error) {
      console.error(error);
    }
  });
};

/** Copy a padded, white-background PNG of the diagram to the clipboard. */
export const captureToClipboard = (event: Event) =>
  exportImage(event, clipboardCopy, { padding: 48, background: '#ffffff' });
