#version 450
layout(location = 0) in vec4 fColor;

layout(location = 0) out vec4 fragColor;

layout(set = 3, binding = 0) uniform _Color {
    vec4 albedo;
};

void main() {
    fragColor = fColor * albedo;
}
