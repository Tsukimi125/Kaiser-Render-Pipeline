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
    public Texture2D noiseTex; //蓝噪声纹理

    [Range(0, 1)]
    public float SSR_Thickness = 0.1f; //SSR分辨率
    
    [Range(0, 10)]
    public int Hiz_MaxLevel = 7;
    [Range(0, 10)]
    public int Hiz_StartLevel = 1;
    [Range(0, 10)]
    public int Hiz_StopLevel = 0;
    [Range(0, 256)]
    public int Hiz_RaySteps = 64;
}