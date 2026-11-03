VARYING vec3 displayColor;

void MAIN()
{
    vec3 s1 = sqrt(max(surfaceColor.rgb, vec3(0.0)));
    vec3 s2 = sqrt(s1);
    vec3 s3 = sqrt(s2);
    displayColor = 0.585122381 * s1 + 0.783140355 * s2 - 0.368262736 * s3;
    POSITION = MODELVIEWPROJECTION_MATRIX * vec4(VERTEX, 1.0);
}
