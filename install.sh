#!/bin/bash

# Check if unzip is installed
if command -v unzip &> /dev/null; then
  echo "unzip is already installed."
else
  echo "unzip is not installed. Installing..."

  # Update package lists (important before installing)
  sudo apt-get update

  # Install unzip
  if sudo apt-get install -y unzip; then
    echo "unzip installed successfully."
  else
    echo "Failed to install unzip."
    exit 1  # Exit with an error code
  fi
fi

exit 0 #Exit with success code
