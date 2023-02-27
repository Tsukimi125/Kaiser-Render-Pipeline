using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

public class ComputeShaderRunner : MonoBehaviour
{
    public ComputeShader shader;

    public RenderTexture tex;

    void Start()
    {
        int kernelHandle = shader.FindKernel("CSMain");

        tex = new RenderTexture(256, 256, 24);
        tex.enableRandomWrite = true;
        tex.Create();

        shader.SetTexture(kernelHandle, "Result", tex);
        shader.Dispatch(kernelHandle, 256 / 8, 256 / 8, 1);

        Texture2D tex2d = new Texture2D(tex.width, tex.height, TextureFormat.RGB24, false);
        RenderTexture.active = tex;
        tex2d.ReadPixels(new Rect(0, 0, tex.width, tex.height), 0, 0);
        tex2d.Apply();

        AssetDatabase.CreateAsset(tex2d, "Assets/test.png");
    }
}
