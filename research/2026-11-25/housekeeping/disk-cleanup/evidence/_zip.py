import zipfile, os, hashlib, time
R=r"E:\rom\release"
for zn in ["TB331FC_HyperOS4_A17_FullKit_v3.zip","TB331FC_HyperOS4_A17_FullKit_v4.zip"]:
    p=os.path.join(R,zn)
    print("="*70); print(zn, os.path.getsize(p), "bytes", time.strftime('%Y-%m-%d %H:%M',time.localtime(os.path.getmtime(p))))
    try:
        z=zipfile.ZipFile(p)
    except Exception as e:
        print("  !! not a valid zip:", e, flush=True)
        with open(p,'rb') as f:
            head=f.read(4); f.seek(-8,2); tail=f.read()
        print("  head",head.hex(),"tail",tail.hex())
        continue
    infos=z.infolist()
    print("  entries:",len(infos)," uncompressed:",sum(i.file_size for i in infos))
    # top-level prefixes
    from collections import Counter
    c=Counter(i.filename.split('/')[0] for i in infos)
    print("  top-level:",dict(c))
    big=[(i.filename,i.file_size) for i in infos if i.file_size>1_000_000]
    for n,s in sorted(big,key=lambda x:-x[1]): print("     %10d  %s"%(s,n))
