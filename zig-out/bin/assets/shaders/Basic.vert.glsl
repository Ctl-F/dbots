#version 450
layout(location = 0) in vec3 vPosition;
layout(location = 1) in vec3 vNormal;
layout(location = 2) in vec2 vUv;
layout(location = 3) in vec3 vColor;

layout(location = 0) out vec4 fColor;
layout(location = 1) out vec2 fUv;
layout(location = 2) out vec3 debugPosition;

layout(set = 1, binding = 0) uniform Transform {
    mat4 projection;
    mat4 view;
    mat4 model;
};

void main() {
    vec4 position = projection * view * model * vec4(vPosition, 1.0);
    fColor = vec4(vColor, 1.0);
    fUv = vUv;

    debugPosition = position.xyz;
    gl_Position = position;
}
