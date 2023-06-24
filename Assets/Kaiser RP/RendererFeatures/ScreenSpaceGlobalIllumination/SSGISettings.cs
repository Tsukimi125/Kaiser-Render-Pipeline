using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

[System.Serializable]
public class SSGISettings
{
    public ComputeShader computeShader;
    [Header("SSGI_Global")]
    [Range(0, 16)]
    public int SSGI_CastRayCount = 1;
    [Range(0, 32)]
    public float SSGI_Intensity = 1;
    [Range(0, 1)]
    public float SSGI_Thickness = 0.1f;
    [Range(0, 1)]
    public float SSGI_ScreenFade = 0.1f;


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

    [Header("Debug")]
    public bool Debug_ColorMask = false;
}