# WATERBOT

## Abstract

This document serves as a high level design doc for the project. 

The goals for this project are:

1. An automated process of irrigating typical garden variety of plants
2. The level of judgement in terms of amount of water and fertilizer should be
   done by the automation system 
3. Cateloging of entities to irrigate should also be taken care of by said
   system
4. Information obtained / observed by the system should also be observable by
   the end user

## Sensors / Categories of information to be gathered

>[!IMPORTANT] 
>At the time of writing perhaps it is still premature to list out the different
>sensors we need. It is therefore more apt for us to first identify the
>different categories of information we need:

**Humidity**:
Of the soil on which the plant is planted.
This is of course an approximiation.

**Visual**: 
Of the plant. This is to gather the following info:

1. What kind of plant is this
2. The state of said plant

>[!NOTE]
>In turn this is to gather info such as how much water it needs
>How much fertilizer it needs. All of this is still pending to actual
>implementation. At the time of writing I am envisioning something akin to the
>following: one time registering of the entity. Once identified, we use the
>identification to retrieve the aforementioned registered information to
>execute the corresponding instructions

>[?QUESTION FOR LATER]
>How do we identify a single plant? 
>This is important to consider because without a reliable way to perform this,
>the system would have to treat the plant as a new comer each time it comes
>across it, thus rendering the previous registered info / instruction invalid.
>
>Ideally, we should be able to distill it down to a single id that corresponds
>to a row of information such as water and fertilizer quantity needed

**Map / Navigation**:
The irrigation ultimately needs to deliver material to different plants and
therefore needs a way to navigate to said plants. For that, we would need a
vehicle capable of performing the following:

- Understand the effective area it needs to cover 
- Understand where it has already been for each dispatch
- Identify the plant perceived and map it to an id in the existing database
- Retrieve humdity information from the corresponding (i.e. nearest) sensor 

>[?QUESTION FOR LATER]
>How do we map the area? We should probably look to robot vacuums to see how
>that is done. Are there existing modules that does that? 

## Server (where data lives) 

The robot would need a way to relay information to a central server. This
server could live on the robot but ideally it should be somewhere that is
always (or relatively speaking with a higher degree of availability than the
robot). Although for the first iteration for simplicity maybe it should just be
hosted on the robot.

The database should have the following information:

- Plant info (indexed by ID), these are what the plant is, its status, last
  measured humidity level, current humidity level, amount of water it needs,
  amount of fertilizer it needs

## Claw Integration

>[!NOTE]
>Not much else other than what I had written below for now... so maybe this
>isn't such a good idea afterall

Enabling the rover with some agency would further improve the functionality of
this product. Some examples of this is:

- Retrieving weather information and performing preemptive measures (e.g.
  keeping the soil moist ahead of hot and sunny days)
