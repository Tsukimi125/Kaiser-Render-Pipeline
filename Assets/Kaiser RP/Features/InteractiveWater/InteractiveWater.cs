using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class InteractiveWater : MonoBehaviour
{
    // Start is called before the first frame update
    public Camera mainCamera;
    public RenderTexture DrawRT;
    public int textreSize = 512;
    void Start()
    {
        mainCamera = Camera.main;
        DrawRT = new RenderTexture(Screen.width, Screen.height, 24);
    }

    RenderTexture CreateRenderTexture()
    {
        RenderTexture rt = new RenderTexture(textreSize, textreSize, 0, RenderTextureFormat.RFloat);
        rt.enableRandomWrite = true;
        rt.Create();
        return rt;
    }

    // Update is called once per frame
    void Update()
    {

    }
}
