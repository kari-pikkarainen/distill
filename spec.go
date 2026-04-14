package main

import (
	"fmt"

	"gopkg.in/yaml.v3"
)

// ImageSpec defines the desired state of a minimal OCI image.
// It is the sole input to the Distill build pipeline.
type ImageSpec struct {
	// Human-readable name for this image.
	Name string `yaml:"name"`

	// Optional description of what this image is for.
	Description string `yaml:"description,omitempty"`

	// Base describes the source distribution used for the chroot bootstrap.
	Base BaseSpec `yaml:"base"`

	// Packages is the explicit list of packages to install into the image.
	// Only these packages (and their hard dependencies) will be present.
	Packages []string `yaml:"packages"`

	// Runtime installs a language runtime sourced directly from upstream
	// (e.g. Temurin, Node.js) rather than from the distro package manager.
	// This allows pinning exact upstream versions independently of the distro.
	Runtime *RuntimeSpec `yaml:"runtime,omitempty"`

	// Accounts defines non-root users and groups to create inside the image.
	Accounts *AccountsSpec `yaml:"accounts,omitempty"`

	// Image contains OCI image configuration applied to the final container.
	Image ImageConfig `yaml:"image,omitempty"`

	// Immutable removes the package manager from the final image, preventing
	// the image from being self-modified at runtime. Defaults to true.
	Immutable *bool `yaml:"immutable,omitempty"`
}

// IsImmutable returns true if the image should have its package manager removed.
// Defaults to true when not set.
func (s *ImageSpec) IsImmutable() bool {
	if s.Immutable == nil {
		return true
	}
	return *s.Immutable
}

// BaseSpec identifies the source distribution for the chroot bootstrap.
type BaseSpec struct {
	// Image is the OCI image reference used as the build host for the chroot.
	// It must have the target distro's package manager available.
	// Examples:
	//   registry.access.redhat.com/ubi9/ubi       (RHEL/UBI9)
	//   debian:bookworm                            (Debian)
	//   ubuntu:24.04                               (Ubuntu)
	Image string `yaml:"image"`

	// Releasever is the distribution release version passed to the package
	// manager. For DNF this is --releasever; for debootstrap this is the
	// suite name (e.g. "bookworm", "noble").
	Releasever string `yaml:"releasever"`

	// PackageManager selects the package manager backend.
	// Supported values: "dnf" (default for RHEL/UBI), "apt" (Debian/Ubuntu).
	// When omitted, Distill infers from the base image.
	PackageManager string `yaml:"packageManager,omitempty"`
}

// RuntimeSpec installs a language runtime from an upstream binary distribution
// rather than from the distro package manager. This gives exact version control
// independent of what the distro packages.
type RuntimeSpec struct {
	// Type identifies the runtime. Supported: "nodejs", "temurin", "python".
	Type string `yaml:"type"`

	// Version is the exact upstream release version to install.
	Version string `yaml:"version"`

	// SHA256 is the expected checksum of the upstream archive.
	SHA256 string `yaml:"sha256"`
}

// AccountsSpec defines the non-root users and groups to create inside the image.
type AccountsSpec struct {
	Groups []GroupSpec `yaml:"groups,omitempty"`
	Users  []UserSpec  `yaml:"users,omitempty"`
}

// GroupSpec defines a group to create inside the image.
type GroupSpec struct {
	Name string `yaml:"name"`
	GID  int    `yaml:"gid"`
}

// UserSpec defines a non-root user to create inside the image.
type UserSpec struct {
	Name  string   `yaml:"name"`
	UID   int      `yaml:"uid"`
	GID   int      `yaml:"gid"`
	Shell string   `yaml:"shell,omitempty"`
	// Groups lists additional groups the user should belong to.
	Groups []string `yaml:"groups,omitempty"`
}

// ImageConfig holds the OCI image configuration for the final container.
type ImageConfig struct {
	// Cmd is the default command and arguments when the container is run.
	Cmd []string `yaml:"cmd,omitempty"`

	// Workdir sets the working directory inside the container.
	Workdir string `yaml:"workdir,omitempty"`

	// Env is a map of environment variables to set in the final image.
	Env map[string]string `yaml:"env,omitempty"`
}

// parseSpec parses an ImageSpec from a YAML string and validates it.
func parseSpec(contents string) (*ImageSpec, error) {
	var spec ImageSpec
	if err := yaml.Unmarshal([]byte(contents), &spec); err != nil {
		return nil, fmt.Errorf("parsing image spec: %w", err)
	}

	if spec.Name == "" {
		return nil, fmt.Errorf("spec must have a name")
	}
	if spec.Base.Image == "" {
		return nil, fmt.Errorf("spec must have a base.image")
	}
	if spec.Base.Releasever == "" {
		return nil, fmt.Errorf("spec must have a base.releasever")
	}
	if len(spec.Packages) == 0 {
		return nil, fmt.Errorf("spec must list at least one package")
	}

	if spec.Base.PackageManager == "" {
		spec.Base.PackageManager = inferPackageManager(spec.Base.Image)
	}

	return &spec, nil
}

// inferPackageManager guesses the package manager from the base image reference.
func inferPackageManager(image string) string {
	for _, prefix := range []string{
		"registry.access.redhat.com/ubi",
		"registry.redhat.io/ubi",
		"quay.io/centos",
		"quay.io/fedora",
		"centos:",
		"fedora:",
		"rockylinux:",
		"almalinux:",
	} {
		if len(image) >= len(prefix) && image[:len(prefix)] == prefix {
			return "dnf"
		}
	}
	for _, prefix := range []string{"debian:", "ubuntu:"} {
		if len(image) >= len(prefix) && image[:len(prefix)] == prefix {
			return "apt"
		}
	}
	// Default to dnf for enterprise images; users can override explicitly.
	return "dnf"
}
