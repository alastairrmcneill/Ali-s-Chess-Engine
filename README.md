# Ali's Chess Engine (ACE)

**A.C.E.** is a chess engine that you can play against on your phone!

Developed in Dart, using the Flutter framework, the engine is available on both iOS and Android devices at the links below!

- [Android](https://play.google.com/store/apps/details?id=com.alastairmcneill.ace)
- [iOS](https://itunes.apple.com/WebObjects/MZStore.woa/wa/viewSoftware?id=6476161902)

#### A.C.E

A.C.E. is a collection of chess engines that get progressively better:

**v0** - Random move selection  
**v1** - Implements a plain negamax algorithm
**v2** - Adds in alpha beta pruning (+38 ELO)
**v3** - Move ordering to improve pruning (+28 ELO)
**v4** - Quiescense search to help avoid horizon effect (+72 ELO) \* this was a modified match with a fixed depth rather than fixed time

This project was inspired by an excellent video by Sebastian Lague [here](https://youtu.be/U4ogK0MIzqk?si=Cy8-raNohwVjh4E-).
