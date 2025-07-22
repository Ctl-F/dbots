#version 450

layout(location = 0) in vec4 fColor;
layout(location = 1) in vec2 fUv;

layout(location = 0) out vec4 fragColor;

layout(set = 2, binding = 0) uniform sampler2D albedo;

layout(set = 3, binding = 0) uniform ColorBlend {
    vec4 blend;
};

void main() {
    fragColor = texture(albedo, fUv);
}
