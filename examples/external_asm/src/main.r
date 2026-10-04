/**
 * External assembly test
 */

int printNum(int x) @("printNum.s");

void main()
{
    int r = printNum(10);
    bios_a(0x3f, "r = %d\n", r);
}
