data=open(r'E:\rom\work\overclock\dtbo_a.img','rb').read(64)
print(data[:32])
print('magic_and_size:', data[0:4].hex())
import struct
print('hdr u32s:', [hex(struct.unpack('<I', data[i:i+4])[0]) for i in range(0,32,4)])
