---
title: kvm系列之二：class和instance
date: 2017-03-01 14:15:41
tags:
---

------
java作为一门面向对象的语言，类和对象是这门语言的核心，就算入门的hello world也需要创建一个类，这个就不如c++那么灵活，但是类似的灵活随之而来的也是语言学习难度的提升。java语言规范的越多，相比c++提供更少的功能或更深层次的封装，也使java入门的门槛降低很多。java作为一门开发效率较高的语言，因此带来的市场占有率的提高与这个必然有相当大的关系。不过这个也是java之前一直被人诟病的地方，代码效率相较于c++低，不过jvm的开发者们一直在致力于提升java的效率，相信不久的将来java的效率会有更大的提升。不过作为广大的使用java作为开发语言的程序员们，这并不都是好处，很多底层的东西会被大家忽略，比如java程序员不用太注重内存的回收，jvm会帮我们完成，而c++程序员需要自己去释放内存，所以如果不注重自己的代码质量的话，可能你可能就离“码农”越来越近了。
本文将从一下三个方面讲述：

* jvm运行期class的结构
* jvm运行期instance的结构
* 类的加载过程

### 运行期class的结构

我们先来看一下kvm运行期间class的结构，代码在VmCommon/h/class.h中，定义了如下：
```
struct classStruct {
    COMMON_OBJECT_INFO(INSTANCE_CLASS)

    UString packageName;            /* Everything before the final '/' */
    UString baseName;               /* Everything after the final '/' */
    CLASS   next;                   /* Next item in this hash table bucket */
    
    unsigned short accessFlags;     /* Access information */
    unsigned short key;             /* Class key */
};
```
结构体classStruct中的COMMON_OBJECT_INFO(INSTANCE_CLASS)字段是Macro，定义如下：
```
/* Macro that defines the most common part of the objects */
#define COMMON_OBJECT_INFO(_type_) \
    _type_ ofClass; /* Pointer to the class of the instance */ \
    monitorOrHashCode mhc;
```
而INSTANCE_CLASS代表的是一个指向instanceClassStruct的指针
```
typedef struct instanceClassStruct* INSTANCE_CLASS
```
instanceClassStruct的结构下面再说，packageName注释写的很明白就是包名（java/lang/Object里的java/lang），baseName就是类名（java/lang/Object里的Object）;CLASS next是用来连接ClassTable中的下一个classStruct结构。accessFlags是？

现在回过头来看instanceClassStruct的结构：
```
struct instanceClassStruct {
    struct classStruct clazz;       /* common info */

    /* And specific to instance classes */
    INSTANCE_CLASS superClass;      /* Superclass, unless java.lang.Object */
    CONSTANTPOOL constPool;         /* Pointer to constant pool */
    FIELDTABLE  fieldTable;         /* Pointer to instance variable table */
    METHODTABLE methodTable;        /* Pointer to virtual method table */
    unsigned short* ifaceTable;     /* Pointer to interface table */
    POINTERLIST staticFields;       /* Holds static fields of the class */
    short   instSize;               /* The size of class instances */
    short status;                   /* Class readiness status */
    THREAD initThread;              /* Thread performing class initialization */
    NativeFuncPtr finalizer;        /* Pointer to finalizer */
};
```
包含一个classStruct的结构体，指向父类的instanceClassStruct的指针，constant pool的指针等（可以从注释中看出来每个字段的意义），这里说一下status字段，这个是表示类加载的状态，类加载的过程后面会讲。

从classStruct和instanceClassStruct的结构中我们可以看出来：每个instanceClassStruct包含一个classStruct，而classStruct又包含指向另一个instanceClassStruct的指针。我们可以套用书里的一句话：

> instanceClassStruct结构中的classStruct结构看成是class的声明，而把整个instanceClassStruct看成是class的定义。

这跟c语言中的声明和定义类似，所以kvm在运行期的每个class在内存中都会对应一个instanceClassStruct结构。这里要再次提一下classStruct Macro中的ofClass，前面说了它指向一个instanceClassStruct，而这个instanceClassStruct就是表示这个class的从属于的class结构。这可能说的比较绕，举个例子，用户自定义的类UserClass，一定是继承于java.lang.Object，也就是instanceClassStruct中的superClass，而这个ofClass就表示java.lang.Class，这三者之间的关系，借用一下书里的图：

回头补

这里大概介绍一下class在kvm运行期内存中的结构，下面开始介绍一下instance的结构。

### 运行期instance的结构

instance的定义也在VmCommon/h/class.h中，结构如下：
```
struct instanceStruct {
    COMMON_OBJECT_INFO(INSTANCE_CLASS)
    union {
        cell *cellp;
        cell cell;
    } data[1];
};
```
这里的COMMON_OBJECT_INFO(INSTANCE_CLASS)和classStruct结构一样，是一个指向instanceStructInstance的指针，这个也好理解，instance是class的实例化的对象。

这里还有一个union，这个是用来做什么的？前面说了，每个instance都从属于一个class，多个instance都是一个class实例化出来的对象，但是我们知道每个instance之间是有区别，也就是instance有共性就是都从属于同一个class，但是他们也有自己的个性，也就是都有自己的实例属性（instance variable），否则就不能称之为面向对象了，而这里的union就是保存每个instanceStruct的instance variable的值的。具体来讲，就是instanceStruct在创建的时候，kvm会根据instanceStructInstance-> instSize创建相应的data[]，里面不仅保存了当前instance的每个variable的值，还会保存相应父类的variable，具体的逻辑就不细讲了，书上说的很清晰。

总结一下，每个instanceStruct都从属于一个instanceClassStruct，又包含一个data[]用来保存自身以及父类各个variable的值。

### 类的加载过程

类在什么情况下会被加载？深入理解Java虚拟机书中是这么说的：

遇到new、getstatic、pustatic和invokestatic这4条字节码指令时，如果类没有进行过初始化，则需要先触发其初始化
使用java.lang.reflect包的方法对类进行反射调用的时候，如果类没有进行过初始化，则需要先触发其初始化
当初始化一个类的时候，如果发现其父类还没有进行过初始化，则需要先触发其父类的初始化
当虚拟机启动时，用户需要指定执行一个主类（包含main()方法的那个类）,虚拟机会先初始化这个主类
当使用JDK 1.7的动态语言支持时，如果一个java.lang.invoke.MethodHandle实例最后的解析结果REF_getStatic、REF_putStatic、REF_invokeStatic的方法句柄，并且这个方法句柄所对应的类没有进行过初始化，则需要先触发其初始化。
这个是针对HotSpot的解释，kvm中除了没有功能之外，其余也适用。但是不同的是类的加载过程，HotSpot的加载过程情况深入理解Java虚拟机的第7章，这里重点说一下kvm的加载过程，主要分4个阶段：

* CLASS_RAW，当kvm在内存中划出一块可以容纳instanceClassStruct结构大小的区域并把它的内容初始化为零，这个class的状态即为CLASS_RAW
* CLASS_LOADING，在CLASS_RAW之后，kvm会从相关的java类中读取该class的内容，也就是instanceClassStruct中各个属性的值，这个状态称之为CLASS_LOADING
* CLASS_LOADED，完成读取之后，class的状态更新为CLASS_LOADED
* CLASS_LINKED，完成上面三部之后，还有一些信息还没有完全被了解，比如实现哪些interface，以及这些interface的内容，kvm获取到这些信息之后会把class的状态更新为CLASS_LINKED
有点晚了，明天详细介绍class的加载过程。

现在继续介绍class的加载过程：

加载class的方法在VmCommon/src/class.c文件中，方法名是getClass，代码如下：
```
CLASS
getClass(const char *name)
{
    if (INCLUDEDEBUGCODE && inCurrentHeap(name)) {
        fatalError(KVM_MSG_BAD_CALL_TO_GETCLASS);
    }
    return getClassX(&name, 0, strlen(name));
}
```
主要就是调用getClassX进行加载，
```
CLASS
getClassX(CONST_CHAR_HANDLE nameH, int offset, int length)
{
    CLASS clazz;
    clazz = getRawClassX(nameH, offset, length);
    if (!IS_ARRAY_CLASS(clazz)) {
        if (((INSTANCE_CLASS)clazz)->status == CLASS_RAW) {
            loadClassfile((INSTANCE_CLASS)clazz, TRUE);
        } else if (((INSTANCE_CLASS)clazz)->status == CLASS_ERROR) {
            START_TEMPORARY_ROOTS
                DECLARE_TEMPORARY_ROOT(char*, className, getClassName(clazz));
                raiseExceptionWithMessage(NoClassDefFoundError, className);
            END_TEMPORARY_ROOTS
        }
    }
    return clazz;
}
```
这个方法主要包含两个逻辑，getRawClassX()和loadClassFile()，分别是前文所提到的进行class的声明（classStruct结构）和定义（instanceClassStruct结构）。getRawClassX()的内容比较多就不贴了，主要就是调用两个函数-change_Name_to_CLASS()和getArrayClass()-来填好这个class在内存中的声明部分，也就是classStruct结构。这里重点说下change_Name_to_CLASS()方法，根据packName计算出一个hash值，并根据这个hash值去classTable中查找具有相同packageName和baseName的classStruct，有的直接返回，没有则在pemGen中开辟一块内存并指定相应的packageName和baseName。此时class的声明部分已完成，继续来看getClassX()方法，如果class的状态是CLASS_RAW则执行loadClassFile()方法，也就是class的定义部分，如果在class的声明部分没有找到相应的class，则抛出相应的异常。loadClassFile()代码也比较长，就不贴了，说几个关键的点：

首先会校验当前class的状态是否为CLASS_RAW，如果不是则抛异常：
```
if (clazz->status != CLASS_RAW)
        fatalVMError(KVM_MSG_EXPECTED_CLASS_STATUS_OF_CLASS_RAW);
```
如果当前的class状态是CLASS_RAW，则把class的状态设置为CLASS_LOADING，然后调用loadRawClass()进行class的定义部分，这个方法执行完成之后则把class状态设置为CLASS_LOADED，并获取class的superClass，然后重复上面的过程：
```
while (clazz != NULL && clazz->status == CLASS_RAW) {
            clazz->status = CLASS_LOADING;
            loadRawClass(clazz, fatalErrorIfFail);
            if (!fatalErrorIfFail && (clazz->status == CLASS_ERROR)) {
                return;
            }
            clazz->status = CLASS_LOADED;

            /*
             * Now go up to the superclass.
             */
            clazz = clazz->superClass;
}
```
这里先介绍一下loadRawClass()，这个方法已经说了是class的定义部分，其实也是superClass的声明部分，这里逐一说明一下这个方法的具体过程：
```
/* Load version info and magic value */
            loadVersionInfo(&ClassFile);
            /* Load and create constant pool */
            IS_TEMPORARY_ROOT(StringPool,
                              loadConstantPool(&ClassFile, CurrentClass));
            /* Load class identification information */
            loadClassInfo(&ClassFile, CurrentClass);
            /* Load interface pointers */
            loadInterfaces(&ClassFile, CurrentClass);
            /* Load field information */
            loadFields(&ClassFile, CurrentClass, &StringPool);
            /* Load method information */
            loadMethods(&ClassFile, CurrentClass, &StringPool);
            /* Load the possible extra attributes (e.g., debug info) */
            ignoreAttributes(&ClassFile, &StringPool);
            ch = loadByteNoEOFCheck(&ClassFile);
            if (ch != -1) {
                raiseExceptionWithMessage(ClassFormatError,
                    KVM_MSG_CLASSFILE_SIZE_DOES_NOT_MATCH);
            }
            /* Ensure that EOF has been reached successfully and close file */
            closeClassfile(&ClassFile);
            /* Make the class an instance of class 'java.lang.Class' */
            CurrentClass->clazz.ofClass = JavaLangClass;
```
先读取class的版本信息，然后在loadConstantPool中调用前面提到的getRawClassX()，来将java类中的存储的superClass字符串转换为classStruct结构，然后存储在class内存中的constant pool中。loadClassInfo()会把super class声明部分设置给class的superClass字段，然后读取class实现了哪些interface信息，其次loadField()会从java类文件中的field[]数组中读取该class的field信息，并存储在fieldStruct结构中。
```
struct fieldStruct {
    NameTypeKey nameTypeKey;
    long        accessFlags; /* Access indicators (public/private etc.) */
    INSTANCE_CLASS ofClass;  /* Backpointer to the class owning the field */
    union { 
        long  offset;        /* for dynamic objects */
        void *staticAddress; /* pointer to static.  */
    } u;
};

struct fieldTableStruct { 
    long length;
    struct fieldStruct fields[1];
};
```
每个字段的信息注释里说的很清楚。再回到loadRawClass()，后面会加载method信息，忽略一写attributes，关闭文件等。

介绍完了loadRawClass()，回头再来看loadClassfile()，此时class和superClass的状态都已经是CLASS_LOADED，主要做两件事，一个是加载class所实现的interface加载到内存，二是设置instance variable相关信息，最后设置class的状态为CLASS_LINKED。

