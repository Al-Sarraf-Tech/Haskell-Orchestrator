Name:           haskell-orchestrator
Version:        %{version}
Release:        1%{?dist}
Summary:        Typed analysis engine for GitHub Actions workflows
License:        MIT
URL:            https://github.com/Al-Sarraf-Tech/Haskell-Orchestrator

%description
Haskell Orchestrator parses workflow YAML into a typed domain model,
validates structure, evaluates 36 configurable policy rules, and
generates deterministic remediation plans.

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/doc/%{name}
cp %{_sourcedir}/orchestrator %{buildroot}/usr/bin/orchestrator
chmod 755 %{buildroot}/usr/bin/orchestrator
cp %{_sourcedir}/README.md %{buildroot}/usr/share/doc/%{name}/
cp %{_sourcedir}/LICENSE %{buildroot}/usr/share/doc/%{name}/
cp %{_sourcedir}/CHANGELOG.md %{buildroot}/usr/share/doc/%{name}/

%files
/usr/bin/orchestrator
/usr/share/doc/%{name}/README.md
/usr/share/doc/%{name}/LICENSE
/usr/share/doc/%{name}/CHANGELOG.md
