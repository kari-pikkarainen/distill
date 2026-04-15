package builder

import (
	"fmt"
	"strings"

	"github.com/damnhandy/distill/internal/spec"
)

// scratchStageInstructions generates the final FROM scratch stage of a
// multi-stage Dockerfile from the OCI image configuration in the spec.
// The builder stage is expected to have populated /chroot with the rootfs.
func scratchStageInstructions(s *spec.ImageSpec) string {
	var b strings.Builder

	b.WriteString("\nFROM scratch\n")
	b.WriteString("COPY --from=builder /chroot /\n")

	for k, v := range s.Image.Env {
		fmt.Fprintf(&b, "ENV %s=%q\n", k, v)
	}

	if s.Image.Workdir != "" {
		fmt.Fprintf(&b, "WORKDIR %s\n", s.Image.Workdir)
	}

	if s.Accounts != nil && len(s.Accounts.Users) > 0 {
		u := s.Accounts.Users[0]
		fmt.Fprintf(&b, "USER %d:%d\n", u.UID, u.GID)
	}

	if len(s.Image.Cmd) > 0 {
		parts := make([]string, len(s.Image.Cmd))
		for i, c := range s.Image.Cmd {
			parts[i] = fmt.Sprintf("%q", c)
		}
		fmt.Fprintf(&b, "CMD [%s]\n", strings.Join(parts, ", "))
	}

	fmt.Fprintf(&b, "LABEL org.opencontainers.image.title=%q\n", s.Name)

	return b.String()
}
