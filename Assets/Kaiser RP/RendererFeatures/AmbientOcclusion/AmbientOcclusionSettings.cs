using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class AmbientOcclusionSettings
{
    // Pass在渲染管线中的执行位置，这里设置为【BeforeRenderingPostProcessing】
    public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    // public Shader shader; //所用Shader
    public ComputeShader computeShader; //所用ComputeShader

    public enum AOType
    {
        SSAO,
        HBAO
    }

    public Texture2D blueNoiseTexture;

    public AOType aoType = AOType.HBAO;

    [Range(0f, 5f)] public float intensity;
    [Range(0f, 32f)] public float aoRadius;

    [Range(0f, 100f)] public float maxDistance;

    [Range(0, 64)] public int directionCount;
    [Range(4, 32)] public int sampleCount;
}