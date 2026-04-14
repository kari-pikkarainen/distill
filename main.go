// Distill builds minimal, immutable OCI images from enterprise Linux base images.
//
// It is a distro-agnostic alternative to Google's distroless images, supporting
// RHEL/UBI (via DNF) and Debian/Ubuntu (via APT) as source distributions.
//
// The core technique is a chroot bootstrap: packages are installed into an
// isolated rootfs directory on the build host using the distro's native package
// manager, then the populated rootfs is copied into a FROM scratch container.
// The package manager itself is never present in the final image.
//
// Usage:
//
//	dagger call build --spec=examples/rhel9-runtime/image.yaml export --path=./output.tar
package main

import (
	"context"
	"fmt"
	"strings"
)

// Distill is the Dagger module. All exported methods are available as Dagger
// pipeline functions via `dagger call`.
type Distill struct{}

// Build produces a minimal OCI container image from a declarative ImageSpec
// YAML file. The image is built from scratch using a chroot bootstrap —
// the package manager runs on the build host and installs into an isolated
// rootfs, which is then copied into a scratch container. The result is a
// fully distribution-derived image with no package manager at runtime.
func (m *Distill) Build(
	ctx context.Context,
	// The ImageSpec YAML file describing the desired image contents.
	spec *File,
	// Target platform for the output image.
	// +optional
	// +default="linux/amd64"
	platform Platform,
) (*Container, error) {
	contents, err := spec.Contents(ctx)
	if err != nil {
		return nil, fmt.Errorf("reading spec file: %w", err)
	}

	imageSpec, err := parseSpec(contents)
	if err != nil {
		return nil, fmt.Errorf("invalid spec: %w", err)
	}

	if platform == "" {
		platform = "linux/amd64"
	}

	switch imageSpec.Base.PackageManager {
	case "dnf":
		return m.buildWithDNF(ctx, imageSpec, platform)
	case "apt":
		return m.buildWithAPT(ctx, imageSpec, platform)
	default:
		return nil, fmt.Errorf("unsupported package manager %q — supported: dnf, apt", imageSpec.Base.PackageManager)
	}
}

// Scan runs a Grype vulnerability scan against the image and fails if any
// findings meet or exceed the specified severity level.
func (m *Distill) Scan(
	ctx context.Context,
	// The container image to scan.
	image *Container,
	// Minimum severity that fails the scan.
	// +optional
	// +default="critical"
	failOn string,
) error {
	if failOn == "" {
		failOn = "critical"
	}

	_, err := dag.Container().
		From("anchore/grype:latest").
		WithMountedFile("/image.tar", image.AsTarball()).
		WithExec([]string{
			"grype", "/image.tar",
			"--fail-on", failOn,
			"--output", "table",
		}).
		Stdout(ctx)
	return err
}

// Attest generates an SPDX SBOM for the image using Syft and returns it as
// a JSON string. The SBOM is generated from the image tarball and captures
// exact package NVRs/NVRAs from the embedded package database.
func (m *Distill) Attest(
	ctx context.Context,
	// The container image to generate an SBOM for.
	image *Container,
) (string, error) {
	sbom, err := dag.Container().
		From("anchore/syft:latest").
		WithMountedFile("/image.tar", image.AsTarball()).
		WithExec([]string{
			"syft", "/image.tar",
			"--output", "spdx-json",
		}).
		Stdout(ctx)
	if err != nil {
		return "", fmt.Errorf("generating SBOM: %w", err)
	}
	return sbom, nil
}

// buildWithDNF implements the chroot bootstrap for RPM-based distributions
// (RHEL, UBI, CentOS Stream, Rocky Linux, AlmaLinux, Fedora).
func (m *Distill) buildWithDNF(ctx context.Context, spec *ImageSpec, platform Platform) (*Container, error) {
	// Persistent DNF cache keyed by releasever so concurrent builds share it.
	dnfCache := dag.CacheVolume(fmt.Sprintf("dnf-%s", spec.Base.Releasever))

	builder := dag.Container(ContainerOpts{Platform: platform}).
		From(spec.Base.Image).
		WithMountedCache("/var/cache/dnf", dnfCache).
		// Create the chroot root and initialize a fresh RPM database inside it.
		// The RPM DB lives in the chroot, not on the build host.
		WithExec([]string{"mkdir", "-p", "/chroot"}).
		WithExec(
			[]string{"rpm", "--root", "/chroot", "--initdb"},
			ContainerWithExecOpts{InsecureRootCapabilities: true},
		).
		// Seed the chroot with the host's repo configuration so DNF can resolve
		// packages against the correct repos for the target releasever.
		WithExec(
			[]string{"bash", "-c", "mkdir -p /chroot/etc && cp -r /etc/yum.repos.d /chroot/etc/"},
			ContainerWithExecOpts{InsecureRootCapabilities: true},
		)

	// Install packages into the chroot using DNF's --installroot flag.
	// --setopt=install_weak_deps=false: skip optional dependencies
	// --setopt=tsflags=nodocs: skip man pages and documentation
	dnfInstall := append([]string{
		"dnf", "install", "-y", "-q",
		"--installroot", "/chroot",
		"--releasever", spec.Base.Releasever,
		"--setopt=install_weak_deps=false",
		"--setopt=tsflags=nodocs",
		"--setopt=override_install_langs=en_US.utf8",
	}, spec.Packages...)

	builder = builder.WithExec(
		dnfInstall,
		ContainerWithExecOpts{InsecureRootCapabilities: true},
	)

	// Create groups and users inside the chroot using the host's groupadd/useradd
	// with the -R flag, which re-roots operations into the chroot.
	if spec.Accounts != nil {
		for _, g := range spec.Accounts.Groups {
			builder = builder.WithExec(
				[]string{"groupadd", "-R", "/chroot", "--gid", fmt.Sprintf("%d", g.GID), g.Name},
				ContainerWithExecOpts{InsecureRootCapabilities: true},
			)
		}
		for _, u := range spec.Accounts.Users {
			shell := u.Shell
			if shell == "" {
				shell = "/sbin/nologin"
			}
			args := []string{
				"useradd", "-R", "/chroot",
				"--uid", fmt.Sprintf("%d", u.UID),
				"--gid", fmt.Sprintf("%d", u.GID),
				"-r", "-m", "-s", shell,
			}
			if len(u.Groups) > 0 {
				args = append(args, "-G", strings.Join(u.Groups, ","))
			}
			args = append(args, u.Name)
			builder = builder.WithExec(args, ContainerWithExecOpts{InsecureRootCapabilities: true})
		}
	}

	// Clean DNF cache inside the chroot.
	builder = builder.WithExec(
		[]string{"dnf", "clean", "all", "--installroot", "/chroot", "--releasever", spec.Base.Releasever},
		ContainerWithExecOpts{InsecureRootCapabilities: true},
	)

	// Remove the package manager binaries and metadata for true immutability.
	// The RPM database is retained for auditability (rpm -qa still works if
	// the rpm binary is present), but dnf/yum cannot install new packages.
	if spec.IsImmutable() {
		builder = builder.WithExec(
			[]string{"bash", "-c", strings.Join([]string{
				"rm -rf",
				"/chroot/usr/bin/dnf*",
				"/chroot/usr/bin/yum*",
				"/chroot/usr/lib/python*/site-packages/dnf*",
				"/chroot/usr/lib/python*/site-packages/yum*",
				"/chroot/var/cache/dnf",
				"/chroot/var/log/dnf*",
				"/chroot/tmp/*",
			}, " ")},
			ContainerWithExecOpts{InsecureRootCapabilities: true},
		)
	}

	return m.assembleImage(spec, platform, builder.Directory("/chroot")), nil
}

// buildWithAPT implements the chroot bootstrap for APT-based distributions
// (Debian, Ubuntu). Uses debootstrap for the initial rootfs.
func (m *Distill) buildWithAPT(ctx context.Context, spec *ImageSpec, platform Platform) (*Container, error) {
	aptCache := dag.CacheVolume(fmt.Sprintf("apt-%s", spec.Base.Releasever))

	builder := dag.Container(ContainerOpts{Platform: platform}).
		From(spec.Base.Image).
		WithMountedCache("/var/cache/apt/archives", aptCache).
		WithExec([]string{"apt-get", "update", "-qq"}).
		WithExec([]string{"apt-get", "install", "-y", "-qq", "debootstrap"}).
		// debootstrap --variant=minbase produces the smallest possible rootfs:
		// only packages marked Essential:yes plus the listed packages.
		WithExec(
			[]string{
				"debootstrap",
				"--variant=minbase",
				fmt.Sprintf("--include=%s", strings.Join(spec.Packages, ",")),
				spec.Base.Releasever,
				"/chroot",
			},
			ContainerWithExecOpts{InsecureRootCapabilities: true},
		)

	if spec.Accounts != nil {
		for _, g := range spec.Accounts.Groups {
			builder = builder.WithExec(
				[]string{"chroot", "/chroot", "groupadd", "--gid", fmt.Sprintf("%d", g.GID), g.Name},
				ContainerWithExecOpts{InsecureRootCapabilities: true},
			)
		}
		for _, u := range spec.Accounts.Users {
			shell := u.Shell
			if shell == "" {
				shell = "/usr/sbin/nologin"
			}
			args := []string{
				"chroot", "/chroot", "useradd",
				"--uid", fmt.Sprintf("%d", u.UID),
				"--gid", fmt.Sprintf("%d", u.GID),
				"-r", "-m", "-s", shell,
			}
			if len(u.Groups) > 0 {
				args = append(args, "-G", strings.Join(u.Groups, ","))
			}
			args = append(args, u.Name)
			builder = builder.WithExec(args, ContainerWithExecOpts{InsecureRootCapabilities: true})
		}
	}

	// Strip APT package lists and cache to reduce final image size.
	builder = builder.WithExec(
		[]string{"bash", "-c", "rm -rf /chroot/var/cache/apt/archives/*.deb /chroot/var/lib/apt/lists/* /chroot/tmp/*"},
		ContainerWithExecOpts{InsecureRootCapabilities: true},
	)

	if spec.IsImmutable() {
		builder = builder.WithExec(
			[]string{"chroot", "/chroot", "dpkg", "--purge", "--force-remove-essential",
				"apt", "apt-utils", "dpkg"},
			ContainerWithExecOpts{InsecureRootCapabilities: true},
		)
	}

	return m.assembleImage(spec, platform, builder.Directory("/chroot")), nil
}

// assembleImage composes the final OCI image from scratch using the populated
// chroot directory and applies OCI configuration from the spec.
func (m *Distill) assembleImage(spec *ImageSpec, platform Platform, rootfs *Directory) *Container {
	image := dag.Container(ContainerOpts{Platform: platform}).
		From("scratch").
		WithDirectory("/", rootfs)

	// Apply environment variables
	for k, v := range spec.Image.Env {
		image = image.WithEnvVariable(k, v)
	}

	if spec.Image.Workdir != "" {
		image = image.WithWorkdir(spec.Image.Workdir)
	}

	if len(spec.Image.Cmd) > 0 {
		image = image.WithDefaultArgs(spec.Image.Cmd)
	}

	// Run as the first defined user, if any
	if spec.Accounts != nil && len(spec.Accounts.Users) > 0 {
		u := spec.Accounts.Users[0]
		image = image.WithUser(fmt.Sprintf("%d:%d", u.UID, u.GID))
	}

	return image
}
