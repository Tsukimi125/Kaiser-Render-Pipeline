using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class HBAOSettings
{
    // Pass在渲染管线中的执行位置，这里设置为【BeforeRenderingPostProcessing】
    public RenderPassEvent passEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    public Shader shader; //所用Shader
    public ComputeShader computeShader; //所用ComputeShader

    public enum AOType
    {
        HBAO,
        GTAO
    }

    public enum Resolution
    {
        Half,
        Full
    }

    public AOType aoType = AOType.HBAO;
    [Range(0f, 5f)] public float intensity;
    [Range(0f, 10f)] public float radius;
    [Range(4, 512)] public float sampleNums;
    [Range(0f, 100f)] public float maxDistance;
}