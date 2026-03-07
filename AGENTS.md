You are preparing the repository for autonomous AI-assisted development.

Purpose:
This document defines the working rules, architecture constraints, and development workflow for AI coding agents contributing to this repository.

The project is an iOS native application called:

Flow

Platform:
iOS Native App

Technology:
Swift + SwiftUI + MapKit

The repository already contains the following design documents:

- Design.md
- ImplementationPlan.md
- Tasks.md

AGENTS.md must instruct AI coding agents how to work within this repository safely and consistently.

Requirements for AGENTS.md

The document must include the following sections.

------------------------------------------------

1. Project Overview

Explain briefly:
- what the Flow application is
- its main goal: visualize mobility flows across South Korea
- the supported transportation modes:
  - Road
  - Rail
  - Air
  - Maritime

Explain that the system visualizes origin-destination movement data across time.

------------------------------------------------

2. Architecture Source of Truth

Explain the role of each design document.

Design.md
- defines system architecture
- defines data model concepts
- defines UI architecture

ImplementationPlan.md
- defines development roadmap
- defines milestones

Tasks.md
- defines executable engineering tasks
- defines priority and dependencies

Rules:
- AI agents must follow these documents
- Do not introduce architecture that contradicts Design.md
- When design changes are necessary, update Design.md first.

------------------------------------------------

3. Repository Structure

Define the expected project structure.

Example:

Flow/
  Core/
  Data/
  Models/
  Services/
  Visualization/
  ViewModels/
  Views/
  Components/
  Resources/

Explain responsibilities:

Core
shared utilities and infrastructure

Models
data structures and domain models

Data
data loading and dataset management

Services
logic services such as filtering engines

Visualization
map rendering logic and flow visualization

ViewModels
application state and business logic

Views
SwiftUI screens

Components
reusable UI components

Resources
assets, sample datasets, configuration files

------------------------------------------------

4. Autonomous Development Workflow

Explain the development loop.

AI agents must follow this workflow:

1. Read Design.md
2. Read ImplementationPlan.md
3. Read Tasks.md
4. Select the next task
5. Plan implementation
6. Implement task
7. Validate completion
8. Update Tasks.md
9. Repeat

Rules:
- implement one task per iteration
- keep commits small
- ensure the app remains compilable.

------------------------------------------------

5. Coding Standards

Define standards for code generation.

Language:
Swift

UI Framework:
SwiftUI

Map Framework:
MapKit

Rules:

- follow MVVM architecture
- keep UI logic in Views
- keep business logic in ViewModels
- keep data loading in Data layer
- keep visualization logic isolated

Other guidelines:

- avoid large monolithic files
- prefer modular components
- maintain clear naming conventions
- write readable Swift code.

------------------------------------------------

6. Data Model Principles

The system should support mobility flow datasets.

Typical model structure:

FlowRecord
origin location
destination location
transport mode
time bucket
flow magnitude

LocationNode
id
name
coordinates
region type

TransportMode
road
rail
air
maritime

Explain that mock datasets should be used first.

------------------------------------------------

7. Map Visualization Guidelines

Map rendering must support:

- flow lines between locations
- transport-mode color differentiation
- scalable visualization
- filtering by transport type
- filtering by time

Visualization logic must remain isolated in the Visualization module.

------------------------------------------------

8. Task Execution Rules

When implementing tasks:

- start with P0 tasks
- respect task dependencies
- implement only one task at a time
- validate Definition of Done.

Tasks.md must be updated after completion.

------------------------------------------------

9. Documentation Rules

When architectural decisions change:

Update:

- Design.md
- ImplementationPlan.md

Do not silently change architecture in code.

------------------------------------------------

10. Safety Constraints

AI agents must avoid:

- rewriting the entire architecture
- implementing large unrelated features
- bypassing Tasks.md
- ignoring dependency order.

Always prefer incremental development.

------------------------------------------------

11. Goal of Early Development

The first iterations should produce:

- working SwiftUI app skeleton
- project architecture structure
- MapKit placeholder map
- mock mobility dataset
- basic flow visualization prototype.

------------------------------------------------

Formatting Rules

- Use Markdown
- Use headings and clear sections
- Use bullet lists for rules
- Keep explanations concise and practical