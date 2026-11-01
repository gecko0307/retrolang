/**
 * SEQ music playback.
 * Plays a looped tune (assets/tune.seq) with instruments from a VAB bank.
 *
 * CROSS    - pause / resume
 * TRIANGLE - restart
 * UP/DOWN  - music volume
 */

#import "retrolib_mini.r"
#import "vab.r"
#import "seq.r"

uchar bankHeader[] @("assets/bank.vh");
uchar bankBody[]   @("assets/bank.vb");
uchar tune[]       @("assets/tune.seq");

void main()
{
    padInit();
    spuInit();

    int bank = vabLoad(bankHeader, bankBody);
    if (bank < 0)
    {
        printf("Failed to load the sound bank\n");
        while (1) { }
    }

    seqInit();
    seqSetPAL(gpuDetectVMode() == VMODE_PAL);

    // The loop markers inside the tune repeat it forever,
    // so there is no need to ask for repeat at the end of the track.
    if (!seqPlay(tune, bank, 0))
    {
        printf("Not a SEQ file\n");
        while (1) { }
    }

    int volume = 127;
    int prev = 0;

    while (1)
    {
        padWaitSync();
        int pad1 = padRead1();
        int pressed = pad1 & ~prev;
        prev = pad1;

        if (pressed & PAD_CROSS)
        {
            if (seqIsPlaying())
            {
                seqPause();
                printf("Paused\n");
            }
            else
            {
                seqResume();
                printf("Resumed\n");
            }
        }

        if (pressed & PAD_TRIANGLE)
        {
            seqPlay(tune, bank, 0);
            printf("Restarted\n");
        }

        if (pad1 & PAD_UP)   { if (volume < 127) volume++; seqSetVolume(volume); }
        if (pad1 & PAD_DOWN) { if (volume > 0)   volume--; seqSetVolume(volume); }

        seqUpdate();
    }
}
