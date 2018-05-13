---
layout:   post
title:    "Breaking an Android app to fix it"
date:     2016-11-20 12:12:03 +0100
category: Android
---
I planned to go to a gym today - I packed, prepared and hurried to my bus stop.
However, when I tried to open First mTicket app, I was greeted with the 
following morbid screen. After trying all possible combinations of device 
reboots and application force stops, I faced reality - I am not getting on a 
bus today. As customer service in First does not work over weekend, I was 
basically stuck without transport till Monday evening in the best case. Buying 
daily/weekly tickets is unfortunately not an option for me now. So, given a lot 
of free time that I got from a night without gym - I sat down determined to 
figure out why the app keeps crashing on the startup.

I connected my phone to my laptop and brought up the Android system log
(`adb logcat`). The following exception was staring back at me every time I 
attempted to start an app (dull bits cut out).

{% highlight ruby %}
E/AndroidRuntime( 3230): FATAL EXCEPTION: main
E/AndroidRuntime( 3230): Process: com.firstgroup.first.mtickets, PID: 3230
E/AndroidRuntime( 3230): java.lang.RuntimeException: java.lang.reflect.InvocationTargetException
E/AndroidRuntime( 3230):  at com.android.internal.os.ZygoteInit.main(ZygoteInit.java:700)
E/AndroidRuntime( 3230): Caused by: java.lang.reflect.InvocationTargetException
E/AndroidRuntime( 3230):  at java.lang.reflect.Method.invoke(Native Method)
E/AndroidRuntime( 3230):  at java.lang.reflect.Method.invoke(Method.java:372)
E/AndroidRuntime( 3230):  at com.android.internal.os.ZygoteInit$MethodAndArgsCaller.run(ZygoteInit.java:905)
E/AndroidRuntime( 3230):  ... 1 more
E/AndroidRuntime( 3230): Caused by: md52ce486a14f4bcd95899665e9d932190b.JavaProxyThrowable:
System.Reflection.TargetInvocationException: Exception has been thrown by the target of an invocation. ---&gt;
System.Runtime.Serialization.SerializationException: serializationStream supports seeking, but its length is 0
...
E/AndroidRuntime( 3230):   at Core.Settings.DeSerializeTicketsLastDisplayed (Android.Content.Context context) [0x00000] in &lt;filename unknown&gt;:0 
E/AndroidRuntime( 3230):   at Core.CoreApplication..ctor (IntPtr javaReference, JniHandleOwnership transfer) [0x00000] in &lt;filename unknown&gt;:0 
E/AndroidRuntime( 3230):   --- End of inner exception stack trace ---
E/AndroidRuntime( 3230): at System.Reflection.MonoCMethod.InternalInvoke (object,object[]) &lt;0x00080&gt;
E/AndroidRuntime( 3230): at System.Reflection.MonoCMethod.DoInvoke (object,System.Reflection.BindingFlags,System.Reflection.Binder,object[],System.Globalization.CultureInfo) &lt;0x00103&gt;
E/AndroidRuntime( 3230): at System.Reflection.MonoCMethod.Invoke
...
E/AndroidRuntime( 3230):  at md5884a0112b7c8ee51cad4c71d498a5924.CoreApplication.n_onCreate(Native Method)
E/AndroidRuntime( 3230):  at md5884a0112b7c8ee51cad4c71d498a5924.CoreApplication.onCreate(CoreApplication.java:19)
E/AndroidRuntime( 3230):  at android.app.Instrumentation.callApplicationOnCreate(Instrumentation.java:1035)
...
{% endhighlight %}

Well, I got lucky pretty much like three times in here! First of all, there is 
no obfuscation on the executable whatsoever. Secondly, it runs on the MonoDroid 
(a.k.a. Xamarin.Android) platform, which I am really familiar with. Finally, 
the exception seems quite easy to prevent. So, let's get to it then! We will 
get the app, decompile it and find out why this exception is thrown.

I used [Online Google Play APK Downloader](http://apk-dl.com/) to quickly grab 
the binaries by the Android package name. Unpacking APK is really 
straightforward, but in case you don't know it is just a special type of ZIP 
archive (specially aligned and with some signature records). With no hesitation 
I headed to the assemblies folder, as this is where all the .NET libraries 
(including the app logic) reside in a MonoDroid application. I had to quickly 
spin up my Windows VM to check the code in JetBrains dotPeek decompiler - and I 
found nothing unexpected whatsoever.

By the way, having settings as a static class is also not really beneficial 
(code maintenance and abstraction after all). Personally, I really like the 
.NET native approach in this case - auto-generated class with an instance in 
Default property. Back to our app, it tries to read the file 
`ticket_last_opened` which is completely empty (zero bytes). So, when the 
application reaches this code it crashes completely because the developer 
forgot (or intentionally decided against?) putting any error-handling logic in 
the method. On the flip side, there is a condition checking for whether the 
file exists - so we could try deleting the file and this should prevent the 
application from crashing in this routine.

You must be already thinking 'dropping a file is be easy' - we will just type 
`rm last_ticket_opened` in the right directory. Well, it really isn't that easy 
on Android - the system is well-protected when you are in production mode. In 
other words, you do not have root access, you do not have file 
ownership/permissions and you cannot use Android run-as trick to access the 
application private data.
{% highlight shell %}
Eric-MacBook:~ Eric$ adb root
adbd cannot run as root in production builds

127|shell@victara:/data/data/com.firstgroup.first.mtickets/files $ ls          
opendir failed, Permission denied

shell@victara:/ $ run-as com.firstgroup.first.mtickets
run-as: Package 'com.firstgroup.first.mtickets' is not debuggable
{% endhighlight %}

Seems like a dead end, as we cannot do it without rooting the phone. Rooting is 
definitely not an option considering that I have banking apps and just 
generally don't want to deal with the security implications of the former.

After playing around with adb and app files, I got another idea - backups! This 
absolutely legitimate way creates a full backup of an application and packs it 
in an easy-to-break AB (Android backup file). Technically, we should be able to 
backup the app private data, delete ticket_last_opened file and restore from 
the corrected backup.

Creating a backup is quite straightforward and comes down to `adb backup` 
command with a couple of parameters. Unpacking a backup - now this was a 
challenge, as console utilities kept failing for me. Quick research showed that 
the reason was that [Android backups use a strange non-compatible Java Deflate algorithm](http://nelenkov.blogspot.co.uk/2012/06/unpacking-android-backups.html).
Luckily, the author of the blog mentioned before has put together a [tool](https://github.com/nelenkov/android-backup-extractor) able to manipulate 
backups easily. At this point, I had an unpacked backup at my disposal.

I deleted the file and packed everything back in and... nothing was restored 
at all! I went back and realised another important thing - order of the files 
in the archive matters (e.g., manifest should always go in as a first file)! By 
changing my tar commands (`tar tf` to generate the file list and `-T` option to 
use it for compression), I managed to get a proper backup onto the device. 
And... Voila! The app was back up and running, as if nothing changed!

The morale of this post is put try-catch blocks in your code and use Android 
backups to meddle with private data of your apps :)
