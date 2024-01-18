# Ali's Chess Engine (ACE)

**A.C.E.** is a chess engine that you can play against on your phone!

Developed in Dart, using the Flutter framework, the engine is available on both iOS and Android devices at the links below!
* [Android](https://play.google.com/store/apps/details?id=com.alastairmcneill.ace)
* [iOS](https://itunes.apple.com/WebObjects/MZStore.woa/wa/viewSoftware?id=6476161902)


#### A.C.E

A.C.E. is a classic chess engine which utilises the **Negamax** algorithm to search through moves in the future to find the optimal move. There were a few enhancements used to optimize the search.

* **Alpha-Beta** - To speed up the search the engine using alpha-beta pruning to cut down the number of branches searched. 
* **Move Ordering** - Alpha-beta pruning is most effective if moves are ordered from best to worst, so before each search takes place, all legal moves are ordered from best to worst which is determined by a score based on capture value.
* **Iterative Deepening** - This approach allows the engine to think for a specific length of time rather than to a given depth. It also helps with move ordering and thus improves the alpha-beta pruning so speeds up the search.

One of the downsides of a tree based search is that the engine can experience the horizon effect, meaning that if the search stops at a given point, with checkmate looming in the next move, it doesn't know that this is a bad position because it hasn't searched far enough. Ideally, the engine could search infinitely far but current computing power doesn't allow this. To help with this **Quiescence Search** was implemented to keep searching until no captures were found. This helps the engine get to a position where there won't be an immediate difference in evaluation after the next move. 

The **Evaluation** for any given positions is handled by comparing the remaining material along with a few additional considerations.

* **Piece Square Tables** - PSTs are used to asign additional weighting to a piece depending on where it is on the board. For example, knights are more impactful in the middle of the board, so the middle squares get a higher score than the edge of the board. 
* **Mop Up** - When the game progresses towards the endgame the tactics change slightly, incentivising the king who is in the lead that time to try and get closer to the opponent to help deliver checkmate. 


Using the search and evaluation algorithms above the engine is able to play at a rating of ~1800 ELO. 


This project was inspired by an excellent video by Sebastian Lague [here](https://youtu.be/U4ogK0MIzqk?si=Cy8-raNohwVjh4E-).