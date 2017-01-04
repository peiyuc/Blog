
# 运行时的数据结构

kvm在执行Java程序时会定义很多的runtime data areas，其中有些是data areas是线程共享的，也有些是线程私有的。下面讲介绍kvm在运行时用到的各个data area.
todo: 补一张内存结构图

### pc register

kvm可以同时执行好几个thread，并且在kvm中具有一个pc register指向正在执行的java指令的地址。这个定义在VmCommon/h/interpret.h中
```
struct GlobalStateStruct { 
    BYTE*         gs_ip; /* Instruction pointer (program counter) */
    cell*         gs_sp; /* Execution stack pointer */
    cell*         gs_lp; /* Local variable pointer */
    FRAME         gs_fp; /* Current frame pointer */
    CONSTANTPOOL  gs_cp; /* Constant pool pointer */
};
```
所以当一个thread交出kvm的使用权时，kvm就会把当时的pc register值存储在代表该thread的内存中，而当下次该thread获取到kvm的使用权是会把该值重新加载到pc register中，用来执行之前暂定时所指执行的java指令的地址。

kvm中每个thread是由一个threadQueue的结构体来代表：
```
struct threadQueue {
    ...
    BYTE* ipStore;  /* Program counter temporary storage (pointer) */
    ...
}
```
结构体字段较多，但是其中的ipStore就是每个thread的pc register。

在任何时间点，每个正在执行的thread的pc register都会包含了正在执行的java instruction的地址。但是如果当前执行的方法是native的话，pc register就没有意义了。

### java heap

kvm启动时就会建立一个java heap，并且有所有thread共享这块内存。kvm中heap包含两个部分：permanent space和heap space。所有和类相关的元数据都会存储在permanent space中，而新建的instance都存储在heap space中。

由于heap space中的对象会被gc回收掉，而permanent space中的元数据不会被gc回收。所以kvm在新加一个class到内存中的时候，kvm会动态改变permanent space的大小，又由于permanent space和heap space共用heap内存，所以heap space的空间也会改变。


（尼玛，图片不能缩小吗？）

hotspot中的heap空间是可以通过设置jvm内存的参数动态改变的，但是kvm是在初始化完成之后就不能改变了。如果遇到内存不足的情况就会跑出一个OOM的异常。

### 运行期常量池

由于java字节码的常量池constant_pool[]索引起来较慢，因此class文件在加载完成之后会生成一个constantPoolStruct的数据结构：


constant pool分三部分： 
entry[0]，保存的是常量池的个数，比如图中的值为5
2、entry[1]-entry[4]，保了具体的常量，数据结构如下：
```
union constantPoolEntryStruct {
    struct {
        unsigned short classIndex;
        unsigned short nameTypeIndex;
    }               method;  /* Also used by Fields */
    CLASS           clazz;
    INTERNED_STRING_INSTANCE String;
    cell           *cache;   /* Either clazz or String */ // 符号引用转化后的直接引用
    cell            integer;
    long            length;
    NameTypeKey     nameTypeKey;
    NameKey         nameKey;
    UString         ustring;
};
```
entry[4]之后的entry是一个字节数组，对应着entry[1]-entry[4]的类型，每个字节有包含两部分，第一位表示常量是否被加载过，后面七位表示常量的类型，具体包含以下几种：
```
#define CONSTANT_Utf8               1
#define CONSTANT_Integer            3
#define CONSTANT_Float              4
#define CONSTANT_Long               5
#define CONSTANT_Double             6
#define CONSTANT_Class              7
#define CONSTANT_String             8
#define CONSTANT_Fieldref           9
#define CONSTANT_Methodref          10
#define CONSTANT_InterfaceMethodref 11
#define CONSTANT_NameAndType        12
```
根据runtime constant pool里的信息获取符号引用，经过解析之后得到直接引用，并更新相应的entry，再次使用时直接使用直接引用，提高jvm性能。