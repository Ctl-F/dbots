#version 450

layout(location = 0) in vec4 fColor;
layout(location = 1) in vec2 fUv;

layout(location = 0) out vec4 fragColor;

layout(set = 2, binding = 0) uniform sampler2D albedo;

layout(set = 3, binding = 0) uniform ColorBlend {
    vec4 blend;
    int show_texture;
};

void main() {
    if (show_texture != 0) {
        float alpha = texture(albedo, fUv).a;
        fragColor = vec4(blend.rgb, blend.a * alpha);
    }
    else {
        fragColor = blend;
    }
}
