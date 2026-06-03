---
title: "Managing Docker Containers with Cursor AI & MCP"
date: 2026-06-03
description: "Exploring how to bridge the gap between AI models and local infrastructure by using natural language in Cursor to deploy and manage a PostgreSQL database via the Model Context Protocol (MCP)."
tags:
  - cursor
  - docker
  - mcp
  - ai
  
categories:
  - homelab writeup
---

<img src="https://cdn.prod.website-files.com/677c400686e724409a5a7409/6790ad949cf622dc8dcd9fe4_nextwork-logo-leather.svg" alt="NextWork" width="300" />

# Create a Docker Container using Cursor

**Project Link:** [View Project](http://learn.nextwork.org/projects/ai-mcp-docker)

**Author:** Chun Kit  
**Email:** chunkit042@gmail.com

---

---

## Introducing Today's Project!

In this project, I am going to use natural language in the Cursor AI-powered code editor to create and manage a PostgreSQL database container via the Model Context Protocol (MCP).

### Key tools and concepts

The key tools I used include Cursor (the AI-powered code editor), Docker Desktop (to run and isolate software), Python, and the uv package manager (to power and execute the background scripts), as well as Docker Compose (to orchestrate multi-container setups) and Adminer (the web interface for visual database management). Key concepts I learnt include the Model Context Protocol (MCP), which bridges the gap between AI models and local development infrastructure, containerization fundamentals (images vs. isolated containers), declarative configuration using YAML files, container networking, and zero-CLI infrastructure monitoring through container logs.

### Challenges and wins

This project took me approximately 45 minutes to complete. The most challenging part was configuring the mcp.json file accurately and ensuring the paths and parameters matched perfectly so that Cursor could establish a green, stable connection to the Docker MCP server without any connection or environment mismatches.

### Why I did this project

I did this project today to learn how to bridge the gap between AI chat models and real-world system infrastructure. Specifically, I wanted to move past using AI just for writing code files and learn how to use natural language to safely spin up, configure, and monitor isolated backend databases without wrestling with complex terminal syntax. Another MCP skill I want to learn is how to connect Cursor to web-browsing or API-fetching MCP servers, so the AI can automatically pull real-time documentation, query live production databases, or interact with cloud platforms like AWS and GitHub repositories directly from my chat pane.

---

## Setting Up Cursor and Docker Desktop

In this step, I'm installing Cursor and Docker Desktop. I need Cursor because it is an AI-powered code editor that allows me to use natural language prompts to control Docker through the Model Context Protocol (MCP). Docker Desktop will help me run, manage, and isolate my PostgreSQL database inside a lightweight container, keeping my local operating system clean.

![Image](http://learn.nextwork.org/charmed_gray_loyal_turtle/uploads/ai-mcp-docker_8h9i0j1k)

### Why Docker containers?

Docker containers are useful because they package an application and all its dependencies together into a lightweight, isolated bundle. This ensures that the application runs exactly the same way on any machine—whether it's your local laptop, a teammate's computer, or a cloud server—without messing up the host operating system's settings or conflicting with other installed software. ---

---

## Connecting Cursor to Docker with MCP

In this step, I'm enabling the Docker MCP which lets Cursor communicate directly with Docker Desktop and manage my container infrastructure using natural language prompts. Instead of just editing text files, this integration allows Cursor's AI chat to run commands, pull images, and spin up or monitor containers like PostgreSQL natively from the editor.

![Image](http://learn.nextwork.org/charmed_gray_loyal_turtle/uploads/ai-mcp-docker_8g9h0i1j)

### Installing Python and uv

To set up the Docker MCP, I installed Python and the uv package manager because the Docker MCP server is built on Python, which acts as the core language running the integration behind the scenes. I needed uv because it is an ultra-fast Python package manager that allows Cursor to seamlessly download, run, and manage the required docker-mcp packages without any tedious manual setup.

### What the Docker MCP can do

The Docker MCP lets me interact with my local Docker daemon directly through Cursor's AI chat using plain English. The actions I can perform using Docker MCP include listing the running or stopped containers on my system, pulling container images from Docker Hub, creating and configuring new containers with custom environment variables, starting and stopping services, and reading container logs to monitor and debug my infrastructure.

---

## Creating My First PostgreSQL Container

In this step, I'm going to use the Docker MCP to spin up a customized PostgreSQL database container with a single natural language prompt. Instead of manually looking up and typing out complex terminal commands, I will simply tell Cursor the exact database parameters I want—such as the database name, username, password, and port mapping—and let the AI orchestrate the deployment natively.

![Image](http://learn.nextwork.org/charmed_gray_loyal_turtle/uploads/ai-mcp-docker_7k8m9n0p)

### Verifying the container

I verified my container by checking Docker Desktop where I can see the my-db container listed inside the Containers tab with a bright green "Running" status icon. This indicates that the container successfully started up in the background and is actively hosting the PostgreSQL database on port 5432, completely isolated from my local machine.

![Image](http://learn.nextwork.org/charmed_gray_loyal_turtle/uploads/ai-mcp-docker_2q3r4s5t)

---

## Orchestrating Multiple Containers with Docker Compose

In this step, I'm setting up a multi-container environment on my Desktop that links my PostgreSQL database with Adminer, a web-based database management tool. Docker Compose will help me define, configure, and launch both of these interconnected containers simultaneously using a single docker-compose.yml file, saving me from having to manage and network them individually.

### Setting up the docker-compose.yml file

I created a docker-compose.yml file that defines the multi-container infrastructure required to run and manage my database ecosystem simultaneously. The two containers running are a PostgreSQL database container (my-db) that safely stores all my data, and an Adminer web interface container (adminer) that runs on port 8081 to let me visually interact with, browse, and manage that database right from my browser.

![Image](http://learn.nextwork.org/charmed_gray_loyal_turtle/uploads/ai-mcp-docker_x7z1b4c6)

### Accessing the database in the browser

I verified my database by logging into Adminer at localhost:8081 where I can see a clean, successful connection to my nextwork database system. The interface shows that the database is currently completely empty, which is exactly what we expect for a brand-new setup, and confirms that our multi-container Docker Compose network is fully working and securely talking to each other.

---

## Monitoring Container Logs

In this project extension, I'm going to use the Docker MCP to inspect my database container's logs directly from Cursor's AI chat without opening a separate terminal window. This will help me understand how backend engineers monitor container health, track the database startup sequence, and catch potential errors or warnings to ensure my infrastructure is running smoothly.

![Image](http://learn.nextwork.org/charmed_gray_loyal_turtle/uploads/ai-mcp-docker_9y0z1a2b)

### What I learned from the logs

I checked my container logs without opening Docker Desktop or running any complex Docker CLI commands in a traditional terminal by sending a natural language prompt directly to Cursor’s AI chat, which utilized the connected Docker MCP to instantly fetch and translate the backend log outputs for me.

---

---
