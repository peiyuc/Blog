---
title: java serialization
date: 2017-03-01 14:15:41
tags:
---

------
序列化是一种约定，大约有两种类型：

* 文本型：xml, json等
* 字节型：java序列化机制

本文重点讲解java的序列化机制
### serialization的使用
本节介绍如何使用java原生的序列化工具，代码如下：

```
public class Person implements Serializable {

    private static final long serialVersionUID = 1L;

    private String name;
    private int age;
    // private static int a = 1;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public static void main(String[] args) throws IOException, ClassNotFoundException {
        Person person = new Person(1);
        person.setName("abc");
        person.setAge(20);

        ObjectOutputStream os = new ObjectOutputStream(new FileOutputStream("person"));
        os.writeObject(person);

        ObjectInputStream is = new ObjectInputStream(new FileInputStream("person"));
        Person p = (Person) is.readObject();
        System.out.println(p.getName());
        System.out.println(p.getAge());
    }

}
```
main函数有具体的使用方法，通过ObjectOutputStream和ObjectInputStream就可以实现序列化和反序列化，使用方法也比较简单，就不详细讲解了。

### 注意事项

* 必须实现Serializable接口，否则会抛如下异常

```
Exception in thread "main" java.io.NotSerializableException: seri.Person
  at java.io.ObjectOutputStream.writeObject0(ObjectOutputStream.java:1184)
  at java.io.ObjectOutputStream.writeObject(ObjectOutputStream.java:348)
  at seri.Person.main(Person.java:38)
  at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
  at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
  at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
  at java.lang.reflect.Method.invoke(Method.java:497)
  at com.intellij.rt.execution.application.AppMain.main(AppMain.java:144)

```
在往文件里写字节的时候就报错了，可以看一下报错的代码，ObjectOutputStream#writeObject0()方法：

```
...
if (obj instanceof String) {
  writeString((String) obj, unshared);
} else if (cl.isArray()) {
    writeArray(obj, desc, unshared);
} else if (obj instanceof Enum) {
    writeEnum((Enum<?>) obj, desc, unshared);
} else if (obj instanceof Serializable) {
    writeOrdinaryObject(obj, desc, unshared);
} else {
    if (extendedDebugInfo) {
      throw new NotSerializableException(
          cl.getName() + "\n" + debugInfoStack.toString());
    } else {
      throw new NotSerializableException(cl.getName());
    }
}
...
```
其中obj instanceof Serializable会判断class是否实现Serializable接口，没有就会抛异常。

* 不会序列化static和transient属性
* 如果序列化的serialVersionUID与反序列化的serialVersionUID不一致会抛如下异常：

```
Exception in thread "main" java.io.InvalidClassException: seri.Person; local class incompatible: stream classdesc serialVersionUID = 1, local class serialVersionUID = 2
  at java.io.ObjectStreamClass.initNonProxy(ObjectStreamClass.java:616)
  at java.io.ObjectInputStream.readNonProxyDesc(ObjectInputStream.java:1623)
  at java.io.ObjectInputStream.readClassDesc(ObjectInputStream.java:1518)
  at java.io.ObjectInputStream.readOrdinaryObject(ObjectInputStream.java:1774)
  at java.io.ObjectInputStream.readObject0(ObjectInputStream.java:1351)
  at java.io.ObjectInputStream.readObject(ObjectInputStream.java:371)
  at seri.Person.main(Person.java:41)
  at sun.reflect.NativeMethodAccessorImpl.invoke0(Native Method)
  at sun.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:62)
  at sun.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43)
  at java.lang.reflect.Method.invoke(Method.java:497)
  at com.intellij.rt.execution.application.AppMain.main(AppMain.java:144)
```

* 可以不声明serialVersionUID常量，但是会留坑，因为jvm会根据class信息生成一个serialVersionUID，如果class发生变更会导致serialVersionUID不一致导致，反序列化失败
* serialVersionUID必须是常量，也就是static和final的，否则就认为没有设置serialVersionUID，代码如下：

```
private static Long getDeclaredSUID(Class<?> cl) {
        try {
            Field f = cl.getDeclaredField("serialVersionUID");
            int mask = Modifier.STATIC | Modifier.FINAL;
            if ((f.getModifiers() & mask) == mask) {
                f.setAccessible(true);
                return Long.valueOf(f.getLong(null));
            }
        } catch (Exception ex) {
        }
        return null;
    }
```

* serialVersionUID需要声明为private
* jvm计算serialVersionUID方法，可以查看ObejctStreamClass#computeDefaultSUID方法
* 子类和父类都需要实现Serializable接口
    - 如果子类实现，但父类没有实现，父类的属性不会被序列化，且父类必须有一个不带参数的构造函数，否则会抛异常
    - 如果父类实现，但子类没有实现，子类可以正常序列化，但是此时子类相当于实现了Serializable接口，但是没有声明serialVersionUID，也会有问题
* 类的所有class属性都必须实现Serializable接口
* enum是实现了Serializable接口的，因此可以进行序列化

```
public abstract class Enum<E extends Enum<E>>
        implements Comparable<E>, Serializable {

}
```
* 可以通过override writeObject()和readObject()方法自定义序列化的方法

### 实战：ArrayList的实现
ArrayList是实现了Serializable接口的，因此可以序列化，但是elementData属性是transient修饰的，根据上一节的说明，该字段不会被序列化，但是我们知道elementData是用来存放组数里的数据的，这个字段不进行序列化就应该有问题，同看查看ArrayList的结构，我们可以看到该类实现了writeObject()和readObject()方法，奥秘就在这两个方法里。

有上面的分析可以知道通过实现writeObject()和readObject()方法，我们可以自定义序列化和反序列化的规则，ArrayList是怎么实现的呢？为什么要进行自定义的序列化和反序列化？

因为ArrayList是基于数组实现的，而且该数组是有冗余的，当容量达到threshold时会进行扩容，所有ArrayList数组里有部分内容是null，在序列化时不需要保存这部分数据，因此ArrayList自定义实现了writeObject()和readObject()方法，只保存非null的数据。

### 源码分析
首先分析ObjectOutputStream的代码，构造函数如下：
```
public ObjectOutputStream(OutputStream out) throws IOException {
    verifySubclass();
    bout = new BlockDataOutputStream(out);
    handles = new HandleTable(10, (float) 3.00);
    subs = new ReplaceTable(10, (float) 3.00);
    enableOverride = false;
    writeStreamHeader();
    bout.setBlockDataMode(true);
    if (extendedDebugInfo) {
        debugInfoStack = new DebugTraceInfoStack();
    } else {
        debugInfoStack = null;
    }
}
```
BlockDataOutputStream是一个二进制数据流，实现了DataOutput接口，可以把基本类型转换成字节输出到流中；

HandleTable是用来保存具体的需要进行序列化的对象的，是一个简单的hash table，包含三个数组：

* Object[]：保存具体对象
* spine[]: 保存对象hash值对应的handle值
* next[]：hash值碰撞之后的handle值链表

ReplaceTable在HandlTable上做的封装，用来表达替换关系，具体如何用后面再说

writeStreamHeader()写入序列化字节头，具体可以查看源码

在写对象的时候会调用java.io.ObjectOutputStream#writeObject，该方法会调用writeObject0()方法