# PlayStation Mesh (PSM)

PSM is a simple static indexed mesh format used by Retrolang examples. It consists of the header followed by vertex data.

Header:

```c
struct PSMHeader
{
    ushort numVerts;
    ushort numTris;
    ushort texWidth;
    ushort texHeight;
    uint uvOffset;
    uint idxOffset;
};
```

`texWidth`, `texHeight` is the size of the texture window used by the mesh. The actual texture page and position within the page must be set by the program.

`uvOffset` and `idxOffset` are from the beginning of the file.

Data:

At offset 16: vertices (8 bytes each, total array size is `numVerts * 8`):

```
short x
short y
short z
short padding
```

At offset `uvOffset`: UV coordinates (2 bytes each, total array size is `numVerts * 2`, entire array is padded to 4-byte alignment):

```
uchar u, v
```

At offset `idxOffset`: triangles (6 bytes each, total array is `numTris * 6`, entire array is padded to 4-byte alignment):

```
ushort vertex1_index
ushort vertex2_index
ushort vertex3_index
```
