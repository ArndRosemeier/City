(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  const reveal = () => {
    const nodes = document.querySelectorAll(".clip-tile, .beat");
    if (reduceMotion || !("IntersectionObserver" in window)) {
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) {
            continue;
          }
          entry.target.classList.add("is-in");
          observer.unobserve(entry.target);
        }
      },
      { threshold: 0.08, rootMargin: "0px 0px -2% 0px" }
    );

    nodes.forEach((node) => {
      node.classList.add("reveal-ready");
      observer.observe(node);
    });
  };

  /**
   * @param {HTMLImageElement} image
   * @param {HTMLElement} list
   * @param {{label: string, src: string}[]} shots
   */
  const bindScreenshots = (image, list, shots) => {
    list.replaceChildren();
    if (shots.length === 0) {
      image.removeAttribute("src");
      image.alt = "";
      return;
    }

    /** @type {HTMLButtonElement[]} */
    const buttons = [];

    for (const [index, shot] of shots.entries()) {
      const li = document.createElement("li");
      const button = document.createElement("button");
      button.type = "button";
      button.setAttribute("role", "option");
      button.setAttribute("aria-selected", index === 0 ? "true" : "false");
      button.dataset.src = shot.src;
      button.dataset.alt = shot.label;

      const name = document.createElement("span");
      name.className = "name";
      name.textContent = shot.label;
      button.append(name);
      li.append(button);
      list.append(li);
      buttons.push(button);
    }

    image.src = shots[0].src;
    image.alt = shots[0].label;

    let swapTimer = 0;

    /**
     * @param {HTMLButtonElement} button
     */
    const select = (button) => {
      const src = button.dataset.src;
      const alt = button.dataset.alt ?? "";
      if (!src) {
        return;
      }

      buttons.forEach((item) => item.setAttribute("aria-selected", item === button ? "true" : "false"));

      if (image.getAttribute("src") === src) {
        return;
      }

      const apply = () => {
        image.src = src;
        image.alt = alt;
        image.classList.remove("is-swap");
      };

      if (reduceMotion) {
        apply();
        return;
      }

      image.classList.add("is-swap");
      window.clearTimeout(swapTimer);
      swapTimer = window.setTimeout(apply, 220);
    };

    list.addEventListener("click", (event) => {
      const target = event.target;
      if (!(target instanceof Element)) {
        return;
      }
      const button = target.closest("button[data-src]");
      if (button instanceof HTMLButtonElement) {
        select(button);
      }
    });

    list.addEventListener("keydown", (event) => {
      const current = document.activeElement;
      if (!(current instanceof HTMLButtonElement) || !buttons.includes(current)) {
        return;
      }
      const index = buttons.indexOf(current);
      if (event.key === "ArrowDown" || event.key === "ArrowRight") {
        event.preventDefault();
        const next = buttons[(index + 1) % buttons.length];
        next.focus();
        select(next);
      } else if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
        event.preventDefault();
        const prev = buttons[(index - 1 + buttons.length) % buttons.length];
        prev.focus();
        select(prev);
      }
    });
  };

  /**
   * @param {HTMLElement} grid
   * @param {{label: string, src: string}[]} clips
   */
  const bindClips = (grid, clips) => {
    grid.replaceChildren();
    for (const clip of clips) {
      const figure = document.createElement("figure");
      figure.className = "clip-tile";

      const video = document.createElement("video");
      video.controls = true;
      video.playsInline = true;
      // Metadata + media fragment so each tile shows that clip's own first frame
      // (not a shared screenshot poster, which made every tile look identical).
      video.preload = "metadata";
      video.src = `${clip.src}#t=0.1`;

      const caption = document.createElement("figcaption");
      caption.className = "clip-meta";
      const strong = document.createElement("strong");
      strong.textContent = clip.label;
      const span = document.createElement("span");
      span.textContent = "In-game capture";
      caption.append(strong, span);

      figure.append(video, caption);
      grid.append(figure);
    }
  };

  /**
   * @param {unknown} data
   * @returns {{screenshots: {label: string, src: string}[], clips: {label: string, src: string}[]}}
   */
  const normalizeGallery = (data) => {
    if (typeof data !== "object" || data === null) {
      throw new Error("gallery data is not an object");
    }
    const screenshots = /** @type {{screenshots?: unknown}} */ (data).screenshots;
    const clips = /** @type {{clips?: unknown}} */ (data).clips;
    if (!Array.isArray(screenshots) || !Array.isArray(clips)) {
      throw new Error("gallery data missing screenshots/clips arrays");
    }
    return {
      screenshots: /** @type {{label: string, src: string}[]} */ (screenshots),
      clips: /** @type {{label: string, src: string}[]} */ (clips),
    };
  };

  const loadGallery = async () => {
    const image = document.querySelector("#district-image");
    const list = document.querySelector("#district-list");
    const grid = document.querySelector("#clip-grid");
    if (!(image instanceof HTMLImageElement) || !(list instanceof HTMLElement) || !(grid instanceof HTMLElement)) {
      throw new Error("gallery mount points missing from page");
    }

    /** @type {{screenshots: {label: string, src: string}[], clips: {label: string, src: string}[]}} */
    let data;
    if (window.ECCENTRI_GALLERY) {
      data = normalizeGallery(window.ECCENTRI_GALLERY);
    } else {
      const response = await fetch("media/gallery.json", { cache: "no-cache" });
      if (!response.ok) {
        throw new Error(`gallery.json failed: HTTP ${response.status}`);
      }
      data = normalizeGallery(await response.json());
    }

    bindScreenshots(image, list, data.screenshots);
    bindClips(grid, data.clips);
    reveal();
  };

  loadGallery().catch((error) => {
    const grid = document.querySelector("#clip-grid");
    const list = document.querySelector("#district-list");
    const message = error instanceof Error ? error.message : String(error);
    console.error(error);
    if (grid instanceof HTMLElement) {
      grid.textContent = `Clips failed to load: ${message}`;
    }
    if (list instanceof HTMLElement) {
      list.textContent = `Screenshots failed to load: ${message}`;
    }
  });
})();
