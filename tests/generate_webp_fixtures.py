#!/usr/bin/env python3
"""Regenerate synthetic WebP regression fixtures (development only).
Requires Pillow with WebP support. Runtime and Pascal tests need neither.
All artwork is generated here; fixtures and this script are 0BSD.
"""
from io import BytesIO
from pathlib import Path
import random
import struct
from PIL import Image, ImageDraw

ROOT = Path(__file__).parent / 'fixtures' / 'webp'
ROOT.mkdir(parents=True, exist_ok=True)
RNG = random.Random(63869649)
manifest = []


def chunk(name, data):
    return name + struct.pack('<I', len(data)) + data + b'\0' * (len(data) & 1)


def riff(body):
    return chunk(b'RIFF', b'WEBP' + body)


def u24(n):
    return n.to_bytes(3, 'little')


def encode(im, lossless=True, method=6, quality=75):
    out = BytesIO()
    im.save(out, format='WEBP', lossless=lossless, exact=True,
            method=method, quality=quality)
    return out.getvalue()


def chunks(data):
    pos = 12
    while pos < len(data):
        n = int.from_bytes(data[pos+4:pos+8], 'little')
        yield data[pos:pos+4], data[pos+8:pos+8+n]
        pos += 8 + n + (n & 1)


def record(name, data, tolerance=0):
    (ROOT / (name + '.webp')).write_bytes(data)
    image = Image.open(BytesIO(data))
    expected = bytearray()
    for frame in range(getattr(image, 'n_frames', 1)):
        image.seek(frame)
        expected.extend(image.convert('RGBA').tobytes('raw', 'BGRA'))
    (ROOT / (name + '.bgra')).write_bytes(expected)
    manifest.append(f'{name}\t{image.width}\t{image.height}\t'
                    f'{getattr(image, "n_frames", 1)}\t{tolerance}')


for name, w, h, kind in [('pixel', 1, 1, 0), ('column', 1, 37, 1),
                         ('row', 43, 1, 1), ('palette', 37, 29, 2),
                         ('noise', 35, 31, 0), ('gradient', 67, 49, 1),
                         ('drawing', 97, 65, 3)]:
    image = Image.new('RGBA', (w, h))
    if kind == 0:
        image.putdata([tuple(RNG.randrange(256) for _ in range(4)) for _ in range(w*h)])
    elif kind == 1:
        image.putdata([((x*7)%256, (y*11)%256, ((x+y)*5)%256, (x*3+y*7)%256)
                       for y in range(h) for x in range(w)])
    elif kind == 2:
        palette = [(255, 0, 0, 255), (0, 255, 0, 128), (0, 0, 255, 0), (0, 0, 0, 255)]
        image.putdata([RNG.choice(palette) for _ in range(w*h)])
    else:
        d = ImageDraw.Draw(image)
        d.rectangle((0, 0, w, h), fill=(20, 40, 60, 255))
        d.rectangle((4, 5, 67, 33), fill=(210, 30, 190, 128))
        d.text((9, 12), 'LazInk WebP', fill=(255, 255, 255, 255))
    record(name + '-lossless', encode(image))
    record(name + '-lossy', encode(image, False, quality=40), 3)

# Uncompressed alpha exercises every inverse filter, independently of an encoder.
w, h = 19, 17
image = Image.new('RGB', (w, h), (70, 100, 150))
vp8 = next(chunk(k, v) for k, v in chunks(encode(image, False)) if k == b'VP8 ')
alpha = [(x*17 + y*23) % 256 for y in range(h) for x in range(w)]
for mode in range(4):
    residual = bytearray()
    for y in range(h):
        for x in range(w):
            i = y*w+x
            if mode == 0 or i == 0:
                p = 0
            elif y == 0:
                p = alpha[i-1]
            elif x == 0:
                p = alpha[i-w]
            elif mode == 1:
                p = alpha[i-1]
            elif mode == 2:
                p = alpha[i-w]
            else:
                p = max(0, min(255, alpha[i-1]+alpha[i-w]-alpha[i-w-1]))
            residual.append((alpha[i]-p) % 256)
    extended = chunk(b'VP8X', b'\x10\0\0\0'+u24(w-1)+u24(h-1))
    record(f'alpha-filter-{mode}', riff(extended+chunk(b'ALPH',bytes([mode*4])+residual)+vp8), 3)

# Explicit subrectangles, replace/blend, dispose/keep, and mixed VP8L/VP8.
w, h = 24, 20
body = chunk(b'VP8X', b'\x12\0\0\0'+u24(w-1)+u24(h-1))
body += chunk(b'ANIM', bytes([33, 22, 11, 77])+struct.pack('<H',2))
for x, y, fw, fh, color, duration, flags, lossless in [
        (0,0,24,20,(50,80,120,128),40,2,True),
        (2,4,12,10,(220,30,40,160),60,0,True),
        (8,2,8,12,(20,210,80,100),80,3,False),
        (0,8,14,8,(180,170,40,190),100,0,True),
        (4,0,16,10,(20,40,220,0),0,2,True)]:
    im = Image.new('RGBA',(fw,fh),color)
    payload = b''.join(chunk(k,v) for k,v in chunks(encode(im,lossless)) if k in (b'ALPH',b'VP8 ',b'VP8L'))
    frame = u24(x//2)+u24(y//2)+u24(fw-1)+u24(fh-1)+u24(duration)+bytes([flags])+payload
    body += chunk(b'ANMF',frame)
record('animation',riff(body),3)
(ROOT / 'manifest.tsv').write_text('\n'.join(manifest)+'\n')
print(f'Wrote {len(manifest)} synthetic fixtures to {ROOT}')
