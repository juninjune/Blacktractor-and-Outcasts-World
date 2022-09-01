using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class CameraSwitch : MonoBehaviour
{
    public Camera[] cameras;

    // Start is called before the first frame update
    void Start()
    {
        if (cameras == null)
            return;

        cameras[0].gameObject.SetActive(true);

        for (int i = 1; i < cameras.Length; i++)
        {
            cameras[i].gameObject.SetActive(false);

        }
    }

    // Update is called once per frame
    void Update()
    {
        
    }

    private void OnGUI()
    {
        float offsetY = 10;

        if (cameras == null)
            return;

        for(int i=0;i<cameras.Length;i++)
        {
            offsetY = 10 + 40 * i;

            if (GUI.Button(new Rect(10,offsetY,100,35),cameras[i].name))
            {
                for(int j=0;j<cameras.Length;j++)
                {
                    if (j==i)
                    {
                        cameras[i].gameObject.SetActive(true);
                    }
                    else
                    {
                        cameras[j].gameObject.SetActive(false);
                    }
                }
            }
        }
    }
}
