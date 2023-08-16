using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class StochasticSSRSettings
{
    public ComputeShader computeShader; //所用ComputeShader

    [Header("SSR_Global")]
    [Range(0, 1)]
    public float SSR_Thickness = 0.1f; //SSR分辨率
    [Range(0, 1)]
    public float SSR_ScreenFade = 0.1f; //SSR屏幕淡出

    [Header("Hiz Trace")]
    [Range(0, 10)]
    public int Hiz_MaxLevel = 7;
    [Range(0, 10)]
    public int Hiz_StartLevel = 1;
    [Range(0, 10)]
    public int Hiz_StopLevel = 0;
    [Range(0, 256)]
    public int Hiz_RaySteps = 64;

    [Header("Filtering")]
    [Range(0, 10)]
    public int Spatial_Resolve = 9;
    [Range(0, 0.99f)]
    [SerializeField]
    public float Temporal_Weight = 0.98f;

    [Range(1, 5)]
    [SerializeField]
    public float Temporal_Scale = 1.25f;

    public enum DebugMode
    {
        None,
        ColorMask,
    }

    [Header("Debug")]
    public DebugMode debugMode = DebugMode.None;

}