{{- define "fabric.chrystokiconf" }}
Chrystoki2 = {
    LibUNIX = /usr/safenet/lunaclient/lib/libCryptoki2_64.so;
    LibUNIX64 = /usr/safenet/lunaclient/lib/libCryptoki2_64.so;
}

Luna = {
  DefaultTimeOut = 500000;
  PEDTimeout1 = 100000;
  PEDTimeout2 = 200000;
  PEDTimeout3 = 10000;
  KeypairGenTimeOut = 2700000;
  CloningCommandTimeOut = 300000;
  CommandTimeOutPedSet = 720000;
}

CardReader = {
  RemoteCommand = 1;
}

Misc = {
   PE1746Enabled = 0;
   ToolsDir = /usr/safenet/lunaclient/bin;
   PartitionPolicyTemplatePath = ./ppt/partition_policy_templates;
   ProtectedAuthenticationPathFlagStatus = 0;
}


LunaSA Client = {
   ReceiveTimeout = 20000;
   SSLConfigFile = /usr/safenet/lunaclient/bin/openssl.cnf;
   ClientPrivKeyFile = /usr/local/luna/config/certs/VMSS01Key.pem;
   ClientCertFile = /usr/local/luna/config/certs/VMSS01.pem;
   ServerCAFile = /usr/local/luna/config/certs/server.pem;
   NetClient = 1;
   TCPKeepAlive = 1;
   {{- range $index, $host := .Values.hsm.hosts }}
   ServerName0{{ $index }} = {{ $host }};
   ServerPort0{{ $index }} = 1792;
   ServerHtl0{{ $index }} = ;
   {{- end }}
}

Secure Trusted Channel = {
   ClientTokenLib = /usr/safenet/lunaclient/lib/libSoftToken.so;
   SoftTokenDir = /usr/local/luna/config/stc/token;
   ClientIdentitiesDir = /usr/local/luna/config/stc/client_identities;
   PartitionIdentitiesDir = /usr/local/luna/config/stc/partition_identities;
}

VirtualToken = {
   VirtualToken00Label = {{ .Values.hsm.label }}ha;
   VirtualToken00SN = {{ .Values.hsm.serialNumber }};
   VirtualToken00Members = {{ .Values.hsm.serialNumber }};
   VirtualTokenActiveRecovery = activeEnhanced;
}

HASynchronize = {
   myha = 1;
}

HAConfiguration = {
   haLogStatus = enabled;
   reconnAtt = -1;
   HAOnly = 1;
}
{{- end }}

