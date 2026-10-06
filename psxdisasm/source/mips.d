module mips;

/**
 * MIPS R3000 instruction codes
 */

enum MipsInstr: ubyte
{
    BXX =   0b000001,
    J =     0b000010,
    JAL =   0b000011,
    
    BEQ =   0b000100,
    BNE =   0b000101,
    BLEZ =  0b000110,
    BGTZ =  0b000111,
    
    ADDI =  0b001000,
    ADDIU = 0b001001,
    SLTI =  0b001001,
    SLTIU = 0b001011,
    
    ANDI =  0b001100,
    ORI =   0b001101,
    XORI =  0b001110,
    LUI =   0b001111,
    
    COP0 =  0b010000,
    COP1 =  0b010001,
    COP2 =  0b010010,
    COP3 =  0b010011,
    
    LB =    0b100000,
    LH =    0b100001,
    LWL =   0b100010,
    LW =    0b100011,
    LBU =   0b100100,
    LHU =   0b100101,
    LWR =   0b100110,
    
    SB =    0b101000,
    SH =    0b101001,
    SWL =   0b101010,
    SW =    0b101011,
    SWR =   0b101110,
    
    LWC0 =  0b110000,
    LWC1 =  0b110001,
    LWC2 =  0b110010,
    LWC3 =  0b110011,
    
    SWC0 =  0b111000,
    SWC1 =  0b111001,
    SWC2 =  0b111010,
    SWC3 =  0b111011,
}

enum MipsRType: ubyte
{
    SLL =   0b000000,
    SRL =   0b000010,
    SRA =   0b000011,
    SLLV =  0b000100,
    SRLV =  0b000110,
    SRAV =  0b000111,
    
    JR =    0b001000,
    JALR =  0b001001,
    
    SYSCALL = 0b001100,
    BREAK = 0b001101,
    
    MFHI =  0b010000,
    MTHI =  0b010001,
    MFLO =  0b010010,
    MTLO =  0b010011,
    
    MULT =  0b011000,
    MULTU = 0b011001,
    DIV =   0b011010,
    DIVU =  0b011011,
    ADD =   0b100000,
    ADDU =  0b100001,
    SUB =   0b100010,
    SUBU =  0b100011,
    
    AND =   0b100100,
    OR =    0b100101,
    XOR =   0b100110,
    NOR =   0b100111,
    
    SLT =   0b101010,
    STLU =  0b101011
}

enum MipsCop0: ubyte
{
    MTC0 =  0b00100,
    MFC0 =  0b00000,
    RFE =   0b10000
}

enum MipsCop2: ubyte
{
    MTC2 =  0b00100,
    MFC2 =  0b00000,
    CTC2 =  0b00110,
    CFC2 =  0b00010
}

enum MipsRegimm: ubyte
{
    BLTZ   = 0b00000, // 0x00
    BGEZ   = 0b00001, // 0x01
    BLTZAL = 0b10000, // 0x10
    BGEZAL = 0b10001  // 0x11
}

alias Reg = ubyte;

// CPU registers
enum: Reg
{
    R0   = 0,
    AT   = 1,
    
    V0   = 2,
    V1   = 3,
    
    A0   = 4,
    A1   = 5,
    A2   = 6,
    A3   = 7,
    
    T0   = 8,
    T1   = 9,
    T2   = 10,
    T3   = 11,
    T4   = 12,
    T5   = 13,
    T6   = 14,
    T7   = 15,
    
    S0   = 16,
    S1   = 17,
    S2   = 18,
    S3   = 19,
    S4   = 20,
    S5   = 21,
    S6   = 22,
    S7   = 23,
    
    T8   = 24,
    T9   = 25,
    
    K0   = 26,
    K1   = 27,
    
    GP   = 28,
    SP   = 29,
    FP   = 30,
    
    RA   = 31
}

// GTE data registers
enum: Reg
{
    VXY0 = 0,  // Vector0 X and Y, 2 packed signed 16-bit integers
    VZ0  = 1,  // Vector0 Z, signed 16-bit integer
    VXY1 = 2,  // Vector1 X and Y, 2 packed signed 16-bit integers
    VZ1  = 3,  // Vector1 Z, signed 16-bit integer
    VXY2 = 4,  // Vector2 X and Y, 2 packed signed 16-bit integers
    VZ2  = 5,  // Vector2 Z, signed 16-bit integer
    RGBC = 6,  // Color/code value, 4 packed unsigned bytes
    OTZ  = 7,  // Average Z value (for Ordering Table), unsigned 16-bit integer
    IR0  = 8,  // 16-bit Accumulator (Interpolate), signed 16-bit integer
    IR1  = 9,  // 16-bit Accumulator (Vector X), signed 16-bit integer
    IR2  = 10, // 16-bit Accumulator (Vector Y), signed 16-bit integer
    IR3  = 11, // 16-bit Accumulator (Vector Z), signed 16-bit integer
    SXY0 = 12, // Screen XY-coordinate FIFO stage1, 2 packed signed 16-bit integers
    SXY1 = 13, // Screen XY-coordinate FIFO stage2, 2 packed signed 16-bit integers
    SXY2 = 14, // Screen XY-coordinate FIFO stage3, 2 packed signed 16-bit integers
    SXYP = 15, // Screen XY-coordinate FIFO stage4, 2 packed signed 16-bit integers
    SZ0  = 16, // Screen Z-coordinate FIFO stage1, unsigned 16-bit integer
    SZ1  = 17, // Screen Z-coordinate FIFO stage2, unsigned 16-bit integer
    SZ2  = 18, // Screen Z-coordinate FIFO stage3, unsigned 16-bit integer
    SZ3  = 19, // Screen Z-coordinate FIFO stage4, unsigned 16-bit integer
    RGB0 = 20, // Color CRGB-code/color FIFO stage1, 4 packed unsigned bytes
    RGB1 = 21, // Color CRGB-code/color FIFO stage2, 4 packed unsigned bytes
    RGB2 = 22, // Color CRGB-code/color FIFO stage3, 4 packed unsigned bytes
    // $23 is undefined/prohibited
    MAC0 = 24, // 32bit Maths Accumulators (Value), signed 32-bit integer
    MAC1 = 25, // 32bit Maths Accumulators (Vector X), signed 32-bit integer
    MAC2 = 26, // 32bit Maths Accumulators (Vector Y), signed 32-bit integer
    MAC3 = 27, // 32bit Maths Accumulators (Vector Z), signed 32-bit integer
    IRGB = 28, // Convert RGB Color (48bit vs 15bit), unsigned 16-bit integer
    ORGB = 29, // 
    LZCS = 30, // Count Leading-Zeroes/Ones (sign bits), 2 packed signed 32-bit integers
    LZCR = 31  // Count Leading-Zeroes/Ones (sign bits), 2 packed signed 32-bit integers
}

// GTE control registers
enum: Reg
{
    R11R12 = 0,  // Rotation matrix 3x3 (r11, r12), 2 signed 16-bit integers
    R13R21 = 1,  // Rotation matrix 3x3 (r13, r21), 2 signed 16-bit integers
    R22R23 = 2,  // Rotation matrix 3x3 (r22, r23), 2 signed 16-bit integers
    R31R32 = 3,  // Rotation matrix 3x3 (r31, r32), 2 signed 16-bit integers
    R33    = 4,  // Rotation matrix 3x3 (r33), signed 16-bit integer
    TRX    = 5,  // Translation vector X, signed 32-bit integer
    TRY    = 6,  // Translation vector Y, signed 32-bit integer
    TRZ    = 7,  // Translation vector Z, signed 32-bit integer
    L11L12 = 8,  // Light source matrix 3x3 (l11, l12), 2 signed 16-bit integers
    L13L21 = 9,  // Light source matrix 3x3 (l13, l21), 2 signed 16-bit integers
    L22L23 = 10, // Light source matrix 3x3 (l22, l23), 2 signed 16-bit integers
    L31L32 = 11, // Light source matrix 3x3 (l31, l32), 2 signed 16-bit integers
    L33    = 12, // Light source matrix 3x3 (l33), signed 16-bit integer
    RBK    = 13, // Background color R, unsigned 32-bit integer
    GBK    = 14, // Background color G, unsigned 32-bit integer
    BBK    = 15, // Background color B, unsigned 32-bit integer
    LR1LR2 = 16, // Light color matrix source (lr1, lr2), 2 signed 16-bit integers
    LR3LG1 = 17, // Light color matrix source (lr3, lg1), 2 signed 16-bit integers
    LG2LG3 = 18, // Light color matrix source (lg2, lg3), 2 signed 16-bit integers
    LB1LB2 = 19, // Light color matrix source (lb1, lb2), 2 signed 16-bit integers
    LB3    = 20, // Light color matrix source (lb3), signed 16-bit integer
    RFC    = 21, // Far color R, unsigned 32-bit integer
    GFC    = 22, // Far color G, unsigned 32-bit integer
    BFC    = 23, // Far color B, unsigned 32-bit integer
    OFX    = 24, // Screen offset X, signed 32-bit integer
    OFY    = 25, // Screen offset Y, signed 32-bit integer
    H      = 26, // Projection plane distance, unsigned 16-bit integer
    DQA    = 27, // Depth queing parameter A (coefficient), signed 16-bit integer
    DQB    = 28, // Depth queing parameter B (offset), unsigned 32-bit integer
    ZSF3   = 29, // Z-averaging scale factor, signed 16-bit integer
    ZSF4   = 30, // Z-averaging scale factor, signed 16-bit integer
    FLAG   = 31  // Flag (read-only), returns any calculation errors, 20 bits
}
