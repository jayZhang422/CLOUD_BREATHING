VARYING vec3 displayColor;

void MAIN()
{
    FRAGCOLOR = vec4(displayColor, surfaceColor.a * surfaceOpacity);
}
