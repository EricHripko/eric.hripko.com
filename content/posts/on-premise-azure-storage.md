---
title: "'On-premise' Azure Storage"
date: 2016-11-20T12:21:31+0100
comments: true
categories:
  - Azure
tags:
  - azure
  - blob
  - emulator
  - storage
---

Recently I needed to extend one of our products with an abstract implementation
of file system access. Specifically, we needed to be able to access files and
directories in both Windows and Azure Blob Storage. After looking for something
suiting our needs online, I could not find anything but
`System.IO.Abstractions`. However, it seemed like a bit of an overkill to use
it for such a small subset of operations. So, I wrote a module from scratch to
ensure that it's both lightweight and fulfils all the requirements given.
Later, I have used the module to implement document synchronisation between
different client workstations based on **Microsoft SyncFramework**.

The system was put in place for a couple of clients, but one client has refused
to put their private documents on the cloud. So, we needed a cost-effective
workaround to ensure that synchronisation works with custom servers.
Unfortunately, there wasn't a straightforward solution or package that one
could install to have Azure Storage on their servers. Suddenly, we realised
that we could use _Azure Storage Emulator_ to store the files and it will be
accessible via the same API as proper Azure Cloud services.

There were a couple of problems along the way before we managed to get the
emulator working fine. First of all, Microsoft doesn't really want you to
download the SDK standalone - so you'll have to find the right installers.
You can do so by going to Azure SDK download page, clicking Previous Versions
and choosing Azure SDK for .NET. Then, download and
install **MicrosoftStorageEmulator.msi** (note, that this requires you to have
**SQL Server LocalDB** installed - I used 2012 version). Secondly, emulator is
only available on localhost by default, so you most likely will have to change
port and/or binding host. In order to do this, go to the
**AzureStorageEmulator.config** and change the appropriate endpoint. Thirdly,
some SDKs (namely, .NET one by Microsoft) may not be fully compatible with
connecting to emulator externally. The only bug that affected our code was
extra prefix in Blob names. Due to the fact that emulator uses the following URL
format `https://host/account/container/blob` as opposed to
`https://account.blob.core.windows.net/container/blob`, SDK has treated the
container name as part of a blob name. So, please account for that if you use
Azure Storage emulator as an external on-premise blob storage. For security
reasons, you might want to setup a HTTPS tunnel for the emulator and change the
default account credentials from pre-configured ones. Finally, to connect to
the emulator externally, you simply need to change the BlobEndpoint property of
the connection string.

P.S.: The only app that supported browsing Azure Storage emulator externally
was [Azure Management Studio by Cerebrata](http://www.cerebrata.com/products/azure-management-studio/introduction). You will only need to change endpoint addresses in preferences.
