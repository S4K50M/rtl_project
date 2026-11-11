# 2×2 NoC traffic benchmark

Latency = source-accepted header to destination-accepted tail. Measurement packets are selected by their header injection window; they remain included when delivered during drain. Configured threshold is **not** offered packets/node/cycle.

 FAST Pattern RateLabel  MeasuredPackets  AcceptedInjectionPacketsPerNodePerCycle  MeanLatencyCycles  P95LatencyCycles  MeasuredDeliveryPacketsPerNodePerCycle  SourceStallNodeCycleFraction  SinkStallNodeCycleFraction
    0 hotspot       low              724                                  0.01810           12.58287              17.0                                 0.01810                       0.00002                     0.03395
    0 hotspot    medium             2577                                  0.06442           15.43888              28.0                                 0.06440                       0.01202                     0.11920
    0 hotspot      high             3583                                  0.08958           22.35641              51.9                                 0.08958                       0.11678                     0.16582
    0 uniform       low              724                                  0.01810           12.44475              17.0                                 0.01810                       0.00002                     0.03500
    0 uniform    medium             2622                                  0.06555           13.31312              19.0                                 0.06552                       0.00160                     0.11822
    0 uniform      high             4055                                  0.10138           14.28237              22.0                                 0.10140                       0.00652                     0.18422
    1 hotspot       low              724                                  0.01810           10.17403              14.0                                 0.01810                       0.00000                     0.03330
    1 hotspot    medium             2595                                  0.06488           13.15337              26.0                                 0.06490                       0.00902                     0.12075
    1 hotspot      high             3603                                  0.09008           21.03802              51.0                                 0.09008                       0.11180                     0.17398
    1 uniform       low              724                                  0.01810           10.03453              14.0                                 0.01810                       0.00000                     0.03598
    1 uniform    medium             2623                                  0.06557           10.76554              16.0                                 0.06552                       0.00042                     0.12152
    1 uniform      high             4079                                  0.10198           11.69968              19.0                                 0.10195                       0.00155                     0.18890
