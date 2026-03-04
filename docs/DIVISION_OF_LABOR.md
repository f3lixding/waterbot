# Division of Labor

Not so much of labor, but really of areas of concerns (that perhaps requires
different area of expertise). They are most likely going to be encountered as
major technical obstacles that would hinder progress. This can also serve as a
good guideline as to what to study.

Keep in mind that I am basing this off of the very limited knowledge I have of
a roomba. As a result some of these might not be applicable for a robot that is
more suitable to be operated our door.

## Mapping / Pathing 

This is the act of exploring the traverseable area. The ultimate output of this
is a map that has the following information:

- The edges / boundary of the traverseable area (In a roomba the edge was
  detected using bumpers to hit the wall. For something that is to be operated
  outdoor we might need another strategy to detect the edge. Maybe we can have
  the exploration to be done in a guided modality where the robot is driven to
  be shown what is considered the valid path)
- Where each point of interest / plant is (this too perhaps needs to be mapped
  out in the aforementioned guided modality)

## Colocation

This is the act of identifying where it is relative to the previously mapped area
For our intents and purposes (i.e. going to each plant and watering it), this
is the allowable area for the robot to move in. 

At the time of writing, what I don't understand is how a roomba is able to
understand where it is after having being lifted off the ground, carried
certain distance away from where it is picked up, and put down again.

## Visual Identification

This is the act of identifying where the root of the plant / nozzle targeting.

## Remote Sensor Reading

These are things such as moisture sensor. Not only do they have to be read,
they also have to be id'd

## Overall Integration / Orchestration

## Choice of chips

This is just researching of different chips to use to achieve the desired functionality
