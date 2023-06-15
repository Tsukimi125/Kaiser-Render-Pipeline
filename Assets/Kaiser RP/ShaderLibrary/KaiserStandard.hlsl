#ifndef KAISER_STANDARD
#define KAISER_STANDARD

float Pow5(float x)
{
    float x2 = x * x;
    return x2 * x2 * x;
}

// float F_Schlick1(float F0, float HoV)
// {
//     return F0 + (1 - F0) * Pow5(1 - HoV);
// }

#endif // KAISER_STANDARD