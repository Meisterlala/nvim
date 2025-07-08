# Winget requirements
$wingetRequirements = @(
    @{ Name = "Zig"; Id = "zig.zig" }
)

# Check if nvim is installed
$nvimPath = Get-Command nvim -ErrorAction SilentlyContinue
if (!$nvimPath) {
    Write-Host "nvim is not installed. Installing with winget..."
    try {
        # Attempt to install nvim using winget
        winget install --id Neovim.Neovim -e --source winget
        Write-Host "nvim installed successfully."
    } catch {
        Write-Error "Failed to install nvim: $($_.Exception.Message)"
    }
} else {
    Write-Host "nvim is already installed. Attempting to update with winget..."
    try {
        winget upgrade --id Neovim.Neovim -e --source winget
        Write-Host "nvim updated successfully."
    } catch {
        Write-Error "Failed to update nvim: $($_.Exception.Message)"
    }
}


# Install all remaining requirements with winget
foreach ($package in $wingetRequirements) {
    $packageName = $package.Name
    $packageId = $package.Id

    $installed = Get-Command $packageName -ErrorAction SilentlyContinue

    if ($installed) {
        Write-Host "$($packageName) is already installed at $($installed.Source)"
    } else {
        Write-Host "$($packageName) is not installed. Installing with winget..."

        try {
            winget install --id $packageId -e --source winget
            Write-Host "$($packageName) installed successfully."
        } catch {
            Write-Error "Failed to install $($packageName): $($_.Exception.Message)"
        }
    }
}
