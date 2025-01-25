@description('Username for the Virtual Machine.')
param adminUsername string = 'AzureAdmin'

@description('Password for the Virtual Machine.')
param adminPassword string = 'ANMtest-2023'

@description('Location for all resources.')
param location string = 'swedencentral'

@description('Number of VNETs and VMs to deploy')
@minValue(1)
@maxValue(254)
param copies int = 20

param vmsize string = 'Standard_D2s_v5'

@description('Prefix Name of VNETs')
param virtualNetworkName string = 'anm-vnet-'
param virtualNetworkTagGr1 string = 'Production'
param virtualNetworkTagGr2 string = 'Development'

@description('Name of the resource group')
param rgName string = resourceGroup().name

@description('remote desktop source address')
param sourceIPaddressRDP string = '217.121.229.32'

@description('Name of the subnet to create in the virtual network')
param subnetName string = 'vmSubnet'
param gwsubnetName string = 'GatewaySubnet'
param bastionsubnetName string = 'AzureBastionSubnet'
param firewallsubnetName string = 'AzureFirewallSubnet'
param firewallmanagementsubnetName string = 'AzureFirewallManagementSubnet'

@description('Prefix name of the nic of the vm')
param nicName string = 'VMNic-'

@description('Prefix name of the nic of the vm')
param vmName string = 'VM-'

@description('Flow log storage account name')
param flowlogSt string = 'flowlog${uniqueString(rgName)}'

//var customImageId = '/subscriptions/0245be41-c89b-4b46-a3cc-a705c90cd1e8/resourceGroups/image-gallery-rg/providers/Microsoft.Compute/galleries/mddimagegallery/images/windows2019-networktools/versions/2.0.0'

var imagePublisher = 'MicrosoftWindowsServer'
var imageOffer = 'WindowsServer'
var imageSku = '2022-Datacenter'

resource prefix 'Microsoft.Network/publicIPPrefixes@2024-05-01' = {
  name: 'prefix'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    prefixLength: 27
  }
}
/*=============================================================SPOKE VNETS========================================================================================*/
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-09-01' = [for i in range(0, copies): {
  name: '${virtualNetworkName}${i}'
  location: location
  tags:{
    group: (i<copies/2 ? virtualNetworkTagGr1 : virtualNetworkTagGr2)
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.${i}.0/24'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.${i}.0/27'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          networkSecurityGroup: {
            id: avnmnsg.id
          }
        }
      }    
      (i==0 || i==copies/2?{
        name: gwsubnetName
        properties: {
          addressPrefix: '10.0.${i}.32/27'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }:{})     
      (i==0 || i==copies/2?{
        name: firewallsubnetName
        properties: {
          addressPrefix: '10.0.${i}.64/26'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }:{}) 
      (i==0 || i==copies/2?{
        name: firewallmanagementsubnetName
        properties: {
          addressPrefix: '10.0.${i}.128/26'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }:{})
      (i==0 || i==copies/2?{
        name: bastionsubnetName
        properties: {
          addressPrefix: '10.0.${i}.192/26'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }:{})
    ]
  }
}]
/*=============================================================NSG========================================================================================*/
resource avnmnsg 'Microsoft.Network/networkSecurityGroups@2022-09-01' = {
  name: 'anvm-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'denyRFC1918-out'
        properties: {
          priority: 150
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          destinationAddressPrefixes: [
            '10.0.0.0/8'
            '172.16.0.0/12'
            '192.168.0.0/24'
          ]
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          sourcePortRange:'*'
        }
      }
    ]
  }
}
/*=============================================================STORAGE========================================================================================*/
resource flowlogst 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: flowlogSt
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}
/*=============================================================FIREWALLS========================================================================================*/
resource hubfirewall 'Microsoft.Network/azureFirewalls@2024-05-01' = [for i in [0, copies/2]: {
  name: 'hubfirewall-${i}'
  location: location
  dependsOn:[
    flowlogst

    hubfirewallpip
    hubfirewallmanagementpip
  ]
  tags:{
    group: virtualNetworkTagGr1
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig'
        properties: {
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', 'anm-vnet-0', firewallsubnetName)
          }
          publicIPAddress: {
              id: resourceId('Microsoft.Network/publicIPAddresses', 'hubfirewallpip-0')
            }
          }
        }
      ]
    managementIpConfiguration: {
        name: 'managementIpConfig'
        properties: {
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', 'anm-vnet-0', firewallmanagementsubnetName)
          }
          publicIPAddress: {
              id: resourceId('Microsoft.Network/publicIPAddresses', 'hubfirewallmanagementpip-0')
            }
          }   
        }
    sku: {
      tier: 'Premium'
      name: 'AZFW_VNet'
    }
    firewallPolicy: {
      id: hubfirewallpolicy.id
    }
  }
}]
resource hubfirewallpip 'Microsoft.Network/publicIPAddresses@2022-09-01' = [for i in [0,copies/2]: {
  name: 'hubfirewallpip-${i}'
  location: location
  sku: {
    tier: 'Regional'
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    publicIPPrefix: {
      id: prefix.id
    }
  }
}]
resource hubfirewallmanagementpip 'Microsoft.Network/publicIPAddresses@2022-09-01' = [for i in [0,copies/2]: {
  name: 'hubfirewallmanagementpip-${i}'
  location: location
  sku: {
    tier: 'Regional'
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    publicIPPrefix: {
      id: prefix.id
    }
  }
}]
/*=============================================================FIREWALL POLICY========================================================================================*/
resource hubfirewallpolicy 'Microsoft.Network/firewallPolicies@2024-03-01' = {
  name: 'hubfirewallpolicy'
  location: location

  properties: {
    sku: {
      tier: 'Premium'
    }
  }
}

resource hubfirewallpolicy_RuleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2020-11-01' = {
  parent: hubfirewallpolicy
  name: 'NetworkRuleCollectionGroup'
  properties: {
    priority: 200
    ruleCollections: [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AllowDNS'
            ipProtocols: [
              'TCP'
              'UDP'
            ]
            sourceAddresses: [
              '*'
            ]
            sourceIpGroups: []
            destinationAddresses: [
              '8.8.8.8'
            ]
            destinationIpGroups: []
            destinationFqdns: []
            destinationPorts: [
              '53'
            ]
          }
        ]
        name: 'AllowNetwork'
        priority: 120
      }
    ]
  }
}  
/*=============================================================BASTIONS========================================================================================*/
resource hubbastion 'Microsoft.Network/bastionHosts@2022-09-01' = [for i in [0,copies/2]: {
  name: 'hubbastion-${i}'
  dependsOn:[
    bastionpip
    virtualNetwork
  ]
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableShareableLink: true
    enableIpConnect: true
    ipConfigurations: [
      {
        name: 'ipConf'
        properties: {
          publicIPAddress: {
            id: bastionpip[((i==0 ? 0 : 1))].id
          }
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', 'anm-vnet-${i}', bastionsubnetName)
          }
        }
      }
    ]
  }
}]

resource bastionpip 'Microsoft.Network/publicIPAddresses@2022-09-01' = [for i in [0,copies/2]: {
  name: 'hubbastionpip-${i}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  zones:[
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    publicIPPrefix: {
      id: prefix.id
    }
  }
}]
/*=============================================================VNET GATEWAYS========================================================================================*/
resource hubgw 'Microsoft.Network/virtualNetworkGateways@2022-09-01' = [for i in [0,copies/2]:{
  name: 'hubgw-${i}'
  location: location
  tags:{
    group: (i<copies/2 ? virtualNetworkTagGr1 : virtualNetworkTagGr2)
  }
  dependsOn: [
    hubgwpubip
    virtualNetwork
  ]
  properties: {
    sku: {
      name: 'VpnGw1AZ'
      tier: 'VpnGw1AZ'
    }
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enablePrivateIpAddress: true
    activeActive: false
    enableBgp: true
    bgpSettings: {
      asn: 64000+i
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: resourceId(rgName, 'Microsoft.Network/publicIPAddresses', 'hubgwpip-${i}')
          }
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', 'anm-vnet-${i}', gwsubnetName)
          }
        }
      }
    ]
  }
}]

resource connlowhigh 'Microsoft.Network/connections@2022-09-01' = {
  name: 'conn-low-high'
  location: location
  properties: {
    connectionType:  'Vnet2Vnet'
    enableBgp: true
    sharedKey: 'tunnelKey'
    virtualNetworkGateway1: {
      id: hubgw[0].id
      properties: {
      }
    }
    virtualNetworkGateway2:{
      properties:{
      }
      id: hubgw[1].id
    }
  }
}

resource connhighlow 'Microsoft.Network/connections@2022-09-01' = {
  name: 'conn-high-low'
  location: location
  properties: {
    connectionType:  'Vnet2Vnet'
    enableBgp: true
    sharedKey: 'tunnelKey'
    virtualNetworkGateway1: {
      id: hubgw[1].id
      properties: {
      }
    }
    virtualNetworkGateway2:{
      properties:{
      }
      id: hubgw[0].id
    }
  }
}

resource hubgwpubip 'Microsoft.Network/publicIPAddresses@2022-09-01' = [for i in [0,copies]:{
  name: 'hubgwpip-${i}'
  location: location
  sku: {
    tier: 'Regional'
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    publicIPPrefix: {
      id: prefix.id
    }
  }
}]
/*=============================================================VIRTUAL MACHINES========================================================================================*/
resource nic 'Microsoft.Network/networkInterfaces@2019-09-01' = [for i in [0,1,2,(copies-2),(copies-1),copies]: {
  name: '${nicName}${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', '${virtualNetworkName}${i}', subnetName)
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}]
resource vm 'Microsoft.Compute/virtualMachines@2018-10-01' = [for i in [0,1,2,(copies/2),(copies/2+1),copies/2+2]: {
  name: '${vmName}${i}'
  location: location
  tags:{
    group: (i<copies/2 ? virtualNetworkTagGr1 : virtualNetworkTagGr2)
  }
  properties: {
    hardwareProfile: {
      vmSize: vmsize
    }
    osProfile: {
      computerName: '${vmName}${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        //id: customImageId
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: 'osDisk-${vmName}${i}'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resourceId('Microsoft.Network/networkInterfaces', '${nicName}${i}')
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
  dependsOn: [
    nic
  ]
}]
resource vmName_Microsoft_Azure_NetworkWatcher 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = [for i in [0,1,2,(copies/2),(copies/2+1),copies/2+2]: {
  name: '${vmName}${i}/Microsoft.Azure.NetworkWatcher'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: 'NetworkWatcherAgentWindows'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
  }
  dependsOn: [
    vm
  ]
}]
resource vmName_IISExtension 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = [for i in [0,1,2,(copies/2),(copies/2+1),copies/2+2]: {
  name: '${vmName}${i}/IISExtension'
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    settings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted Add-WindowsFeature Web-Server; powershell -ExecutionPolicy Unrestricted Add-Content -Path "C:\\inetpub\\wwwroot\\Default.htm" -Value $($env:computername)'
    }
    protectedSettings: {
    }
  }
  dependsOn: [
    vm
   ]
}]
/*===================================AVNM============================================================*/
resource avnm 'Microsoft.Network/networkManagers@2022-09-01' = {
  name: 'avnm'
  location: location
  properties: {
    networkManagerScopeAccesses: [
      'Connectivity'
      'SecurityAdmin'
    ]
    networkManagerScopes: {
      subscriptions: [
        subscription().id
      ]
    }
  }
}
resource prodnetworkgr 'Microsoft.Network/networkManagers/networkGroups@2022-09-01' = {
  name: 'production-networkgroup'
  parent: avnm
  dependsOn:[
    virtualNetwork
  ]
  properties: {
    
  }
}
resource devnetworkgr 'Microsoft.Network/networkManagers/networkGroups@2022-09-01' = {
  name: 'development-networkgroup'
  parent: avnm
  dependsOn:[
    virtualNetwork
  ]
  properties: {
    
  }
}

resource networkgr1_static 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2022-09-01' = [for c in range(1,copies/2-1): {
  name: 'production_${c}'
  parent: prodnetworkgr
  dependsOn:[
    virtualNetwork
  ]
  properties: {
    resourceId: virtualNetwork[c].id
    } 
}]
resource networkgr2_static 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2022-09-01' = [for c in range(copies/2,copies/2-1): {
  name: 'development_${c-(copies/2)}'
  parent: devnetworkgr
  dependsOn:[
    virtualNetwork
    networkgr1_static
  ]
  properties: {
    resourceId: virtualNetwork[c].id
    } 
}]

resource prodhubspokemesh 'Microsoft.Network/networkManagers/connectivityConfigurations@2022-09-01' = {
  name: 'production-hubspokemesh'
  parent: avnm
  dependsOn:[
    virtualNetwork
  ]
  properties: {
    appliesToGroups: [
      {
        groupConnectivity: 'DirectlyConnected'
        isGlobal: 'True'
        networkGroupId: prodnetworkgr.id
        useHubGateway: 'True'
      }
   ] 
    connectivityTopology: 'HubAndSpoke'
    hubs: [
      {
        resourceType: 'Microsoft.Network/virtualNetworks'
        resourceId: virtualNetwork[0].id
      }
      
    ]
    deleteExistingPeering: 'True'
    isGlobal: 'True'
  }
}
resource devhubspokemesh 'Microsoft.Network/networkManagers/connectivityConfigurations@2022-09-01' = {
  name: 'development-hubspokemesh'
  parent: avnm
  dependsOn:[
    virtualNetwork
  ]
  properties: {
    appliesToGroups: [
      {
        groupConnectivity: 'DirectlyConnected'
        isGlobal: 'True'
        networkGroupId: devnetworkgr.id
        useHubGateway: 'True'
      }
   ] 
    connectivityTopology: 'HubAndSpoke'
    hubs: [
      {
        resourceType: 'Microsoft.Network/virtualNetworks'
        resourceId: virtualNetwork[copies].id
      }
      
    ]
    deleteExistingPeering: 'True'
    isGlobal: 'True'
  }
}

resource secadminrule 'Microsoft.Network/networkManagers/securityAdminConfigurations@2022-09-01' = {
  name: 'secadminrule'
  parent: avnm
  properties: {    
  }
}

resource secadminrulecollall 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2022-07-01' = {
  name: 'secadminrulecollall'
  parent: secadminrule

  properties: {
    appliesToGroups: [
      {
        networkGroupId: prodnetworkgr.id
      }
      {
        networkGroupId: devnetworkgr.id
      }
    ] 
  }
}
resource nointernet 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2022-04-01-preview'= {
  name: 'no-internet'
  parent: secadminrulecollall
  kind: 'Custom'
  properties: {
    priority: 1000
    access: 'Deny'
    direction: 'Outbound'
    protocol: 'Any'
    sourcePortRanges:[
      '0-65535'
    ]
    destinationPortRanges:[
      '0-65535'
    ]
    sources: [
      {
        addressPrefixType: 'IPPrefix'
        addressPrefix: '*'
      }
    ]
    destinations: [
      {
        addressPrefixType: 'IPPrefix'
        addressPrefix: '*'
      }
    ]
  }
}
resource secadminrulecollprod 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2022-09-01' = {
  name: 'secadminrulecoll-production'
  parent: secadminrule
  properties: {
    appliesToGroups: [
      {
        networkGroupId: prodnetworkgr.id
      }
    ] 
  }
}

resource allowprod 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2022-04-01-preview'= [for c in range(0,copies/2): {
  name: 'allowprod-${c}'
  parent: secadminrulecollprod
  kind: 'Custom'
  properties: {
    priority: 400+c
    access: 'allow'
    direction: 'Outbound'
    protocol: 'Any'
    sourcePortRanges:[
      '0-65535'
    ]
    destinationPortRanges:[
      '0-65535'
    ]
    sources: [
      {
        addressPrefixType: 'IPPrefix'
        addressPrefix: '*'
      }
    ]
    destinations: [
      {
        addressPrefixType: 'IPPrefix'
        addressPrefix: '10.0.${c}.0/24'
      }
    ]
  }
}]

resource secadminrulecolldev 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections@2022-09-01' = {
  name: 'secadminrulecoll-development'
  parent: secadminrule

  properties: {
    appliesToGroups: [
      {
        networkGroupId: devnetworkgr.id
      }
    ] 
  }
}

resource allowdev 'Microsoft.Network/networkManagers/securityAdminConfigurations/ruleCollections/rules@2022-04-01-preview'= [for c in range(copies/2,copies): {
  name: 'allowdev-${c}'
  parent: secadminrulecolldev
  kind: 'Custom'
  properties: {
    priority: 400+c
    access: 'allow'
    direction: 'Outbound'
    protocol: 'Any'
    sourcePortRanges:[
      '0-65535'
    ]
    destinationPortRanges:[
      '0-65535'
    ]
    sources: [
      {
        addressPrefixType: 'IPPrefix'
        addressPrefix: '*'
      }
    ]
    destinations: [
      {
        addressPrefixType: 'IPPrefix'
        addressPrefix: '10.0.${c}.0/24'
      }
    ]
  }
}]

