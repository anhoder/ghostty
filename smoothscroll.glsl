// Minimal pixel-level smooth scrolling shader for Ghostty.
//
// Reads iPendingScroll (sub-cell scroll remainder, in pixels) exposed by the
// renderer and vertically offsets the terminal image by that amount. This
// lets a trackpad / high-resolution wheel rest partway through a cell instead
// of snapping to whole rows.
//
// Usage (in ghostty config):
//   custom-shader = ./smoothscroll.glsl
//   custom-shader-animation = true
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragCoord -= iPendingScroll;
    fragColor = texture(iChannel0, fragCoord / iResolution.xy);
}
