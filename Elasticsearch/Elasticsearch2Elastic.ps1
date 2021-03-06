#Requires -version 3.0
#ElasticSearch Cluster to Monitor
$elasticServer = "http://server1:9200"
$interval = 60

#ElasticSearch Cluster to Send Metrics
$elasticIndex = "elasticsearch_prod_metrics"
$elasticMonitoringCluster = "http://server2:9200"

function SendTo-Elasticsearch ($json, $elasticMonitoringCluster, $elasticIndex, $indexDate)
{
    try
    {
       Invoke-RestMethod "$elasticMonitoringCluster/$elasticIndex-$indexDate/message" -Method Post -Body $json -ContentType 'application/json'
    }
       catch [System.Exception]
       {
           Write-Host "SendTo-Elasticsearch exception - $_"
       } 
}

function Get-ElasticsearchClusterStats ($elasticServer)
{
    $indexDate = [DateTime]::UtcNow.ToString("yyyy.MM.dd")

    try
    {
        #Cluster Health
        $a = Invoke-RestMethod -Uri "$elasticServer/_cluster/health"
        $ClusterName = $a.cluster_name
        $a | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
 	if ($a.status -eq "green")
            {$a | add-member -Name "status_code" -Value 0 -MemberType NoteProperty}
        elseif ($a.status -eq "yellow")
            {$a | add-member -Name "status_code" -Value 1 -MemberType NoteProperty}
        elseif ($a.status -eq "red")
            {$a | add-member -Name "status_code" -Value 2 -MemberType NoteProperty}
        $json = $a | convertTo-json
        SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticIndex $indexDate

        #Cluster Stats
        $a = Invoke-RestMethod -Uri "$elasticServer/_cluster/stats"
        $a | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        $json = $a | ConvertTo-Json -Depth 7
        SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticIndex $indexDate

        #Get Nodes
        $nodesraw = Invoke-RestMethod -Uri "$elasticServer/_cat/nodes?v&h=n"
        $nodes = $nodesraw -split '[\n]' | select -skip 1 | ? { $_ -ne "" } | % { $_.Replace(" ","") }

        #Node Stats
        foreach ($node in $nodes)
            {
            $a = Invoke-RestMethod -Uri "$elasticServer/_nodes/$node/stats"
            $nodeID = ($a.nodes | gm)[-1].Name
            $a.nodes.$nodeID | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
            $a.nodes.$nodeID | add-member -Name "cluster_name" -Value $ClusterName -MemberType NoteProperty
            $json = $a.nodes.$nodeID | ConvertTo-Json -Depth 7
            SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticIndex $indexDate
            }

        #Index Stats
        $a = Invoke-RestMethod -Uri "$elasticServer/_stats"
        $a._all | add-member -Name "@timestamp" -Value ([DateTime]::Now.ToUniversalTime().ToString("o")) -MemberType NoteProperty
        $a._all | add-member -Name "cluster_name" -Value $ClusterName -MemberType NoteProperty
        $json = $a._all | ConvertTo-Json -Depth 7
        SendTo-Elasticsearch $json $elasticMonitoringCluster $elasticIndex $indexDate

    }
       catch [System.Exception]
       {
           Write-Host "Get-ElasticsearchClusterStats exception - $_"
       } 
}


while ($true)
{
    if ((get-date) -ge $nextRun)
    {
        $nextRun = (get-date).AddSeconds($interval)
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        Get-ElasticsearchClusterStats $elasticServer
		"Total Elapsed Time: $($elapsed.Elapsed.ToString())"
        $TimeDiff = NEW-TIMESPAN –Start (get-date) –End $nextRun
    }

 if ([int]$($TimeDiff.TotalSeconds) -le 0) {}
    else {
        Write-Output "Sleeping $($TimeDiff.TotalSeconds) seconds"
        sleep $($TimeDiff.TotalSeconds)
    }
    $TimeDiff = 0
}
