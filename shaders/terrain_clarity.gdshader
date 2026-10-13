shader_type canvas_item;
render_mode unshaded;

// Gentle grading of the existing map; no new geometry or texture detail.
// Defaults keep the local brightness correction below 1.2 percentage points.
uniform float sharpen_strength : hint_range(0.0, 0.3, 0.01) = 0.18;
uniform float detail_limit : hint_range(0.0, 0.03, 0.001) = 0.012;
uniform float contrast : hint_range(1.0, 1.08, 0.005) = 1.03;
uniform float brightness : hint_range(0.0, 0.03, 0.001) = 0.014;

varying vec4 terrain_modulate;

float luminance(vec3 rgb) {
    return dot(rgb, vec3(0.2126, 0.7152, 0.0722));
}

void vertex() {
    // In fragment(), Godot's COLOR already includes a texture sample.
    // Carry the vertex modulation separately to avoid sampling it twice.
    terrain_modulate = COLOR;
}

void fragment() {
    vec4 base = texture(TEXTURE, UV);
    vec2 texel = TEXTURE_PIXEL_SIZE;
    vec3 neighbours = (
        texture(TEXTURE, UV + vec2(texel.x, 0.0)).rgb
        + texture(TEXTURE, UV - vec2(texel.x, 0.0)).rgb
        + texture(TEXTURE, UV + vec2(0.0, texel.y)).rgb
        + texture(TEXTURE, UV - vec2(0.0, texel.y)).rgb
    ) * 0.25;

    // Source texels per rendered pixel. Fade sharpening out when the map
    // is reduced: it otherwise emphasizes flicker in tiny trees and fields.
    float footprint = max(length(dFdx(UV) / texel), length(dFdy(UV) / texel));
    float zoom_weight = 1.0 - smoothstep(1.0, 2.0, footprint);
    float detail = clamp(
        (luminance(base.rgb) - luminance(neighbours)) * sharpen_strength,
        -detail_limit,
        detail_limit
    ) * zoom_weight;

    // One scalar correction preserves the original relative colour channels.
    vec3 graded = (base.rgb + vec3(detail) - vec3(0.5)) * contrast
        + vec3(0.5 + brightness);
    COLOR = vec4(clamp(graded, vec3(0.0), vec3(1.0)), base.a) * terrain_modulate;
}
