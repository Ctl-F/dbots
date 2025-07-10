#version 450
layout(location = 0) in vec3 vPosition;
layout(location = 1) in vec3 vColor;
layout(location = 2) in vec2 vUv;

layout(location = 0) out vec4 fColor;
layout(location = 1) out vec2 fUv;

void main() {
    gl_Position = vec4(vPosition, 1.0);
    fColor = vec4(vColor, 1.0);
    fUv = vUv;
}
