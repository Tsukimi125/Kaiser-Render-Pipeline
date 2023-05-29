using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class SSRTSettings
{
    // Pass在渲染管线中的执行位置，这里设置为【BeforeRenderingPostProcessing】
    public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    public Shader shader; //所用Shader
    public ComputeShader computeShader; //所用ComputeShader
    public Texture2D blueNoiseTexture; //蓝噪声纹理

}