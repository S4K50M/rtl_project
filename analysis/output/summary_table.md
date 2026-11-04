# 2×2 NoC traffic benchmark

Latency = source-accepted header to destination-accepted tail. Measurement packets are selected by their header injection window; they remain included when delivered during drain. Configured threshold is **not** offered packets/node/cycle.

 FAST Pattern RateLabel  MeasuredPackets  AcceptedInjectionPacketsPerNodePerCycle  MeanLatencyCycles  P95LatencyCycles  MeasuredDeliveryPacketsPerNodePerCycle  SourceStallNodeCycleFraction  SinkStallNodeCycleFraction
    0 hotspot       low              724                                  0.01810           12.58287              17.0                                 0.01810                       0.00002                     0.03395
    0 hotspot    medium             2577                                  0.06442           15.43888              28.0                                 0.06440                       0.01202                     0.11920
    0 hotspot      high             3583                                  0.08958           22.35641              51.9                                 0.08958                       0.11678                     0.16582
    0 uniform       low              724                                  0.01810           12.44475              17.0                                 0.01810                       0.00002                     0.03500
    0 uniform    medium             2622                                  0.06555           13.31312              19.0                                 0.06552                       0.00160                     0.11822
    0 uniform      high             4055                                  0.10138           14.28237              22.0                                 0.10140                       0.00652                     0.18422
