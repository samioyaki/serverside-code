use std::{
    env,
    error::Error,
    fs::{self, File},
    io::{BufReader, BufWriter, Write},
    path::{Path, PathBuf},
};

use rbx_dom_weak::{types::Ref, InstanceBuilder, WeakDom};

const PRESERVED_PATHS: &[&[&str]] = &[
    &["ReplicatedStorage", "Remotes"],
    &["ReplicatedStorage", "Assets"],
    &["ReplicatedStorage", "Assets", "Baddies"],
    &["Workspace", "Game"],
];

fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 && args.len() != 5 {
        eprintln!(
            "Usage: rojo-place-merge <base-place.rbxl> <rojo-built-place.rbxl> <output.rbxl> [baddie-models-dir]"
        );
        std::process::exit(2);
    }

    let base_path = Path::new(&args[1]);
    let source_path = Path::new(&args[2]);
    let output_path = Path::new(&args[3]);

    let mut base_dom = read_place(base_path)?;
    let source_dom = read_place(source_path)?;

    sync_direct_children(
        &source_dom,
        &mut base_dom,
        &["ReplicatedStorage"],
        &["Assets", "Remotes"],
    )?;
    sync_direct_children(&source_dom, &mut base_dom, &["ServerScriptService"], &[])?;
    sync_direct_children(
        &source_dom,
        &mut base_dom,
        &["StarterPlayer", "StarterPlayerScripts"],
        &[],
    )?;

    for path in PRESERVED_PATHS {
        ensure_path_from_source(&source_dom, &mut base_dom, path)?;
    }

    let imported_models = if args.len() == 5 {
        import_baddie_models(&mut base_dom, Path::new(&args[4]))?
    } else {
        0
    };

    let source_script_count = count_scripts(&source_dom);
    let output_script_count = count_scripts(&base_dom);
    if output_script_count != source_script_count {
        return Err(format!(
            "refusing to publish: source contains {source_script_count} scripts but merged place contains {output_script_count}; remove unexpected embedded scripts"
        )
        .into());
    }

    let baddies_parent = find_path(&base_dom, &["ReplicatedStorage", "Assets", "Baddies"])
        .ok_or("merged baddie assets folder was not found")?;
    let baddie_unsafe_count = count_unsafe_below(&base_dom, baddies_parent);
    if baddie_unsafe_count != 0 {
        return Err(format!(
            "refusing to publish: merged baddie assets still contain {baddie_unsafe_count} unsafe instances"
        )
        .into());
    }

    let temp_output_path = output_path.with_extension("rbxl.tmp");
    write_place(&temp_output_path, &base_dom)?;
    fs::rename(&temp_output_path, output_path)?;

    println!(
        "Merged {} Rojo scripts and {} sanitized baddie models into {}",
        source_script_count,
        imported_models,
        output_path.display()
    );

    Ok(())
}

fn import_baddie_models(dest: &mut WeakDom, models_dir: &Path) -> Result<usize, Box<dyn Error>> {
    let baddies_parent = find_path(dest, &["ReplicatedStorage", "Assets", "Baddies"])
        .ok_or("destination ReplicatedStorage/Assets/Baddies was not found")?;
    let mut paths: Vec<PathBuf> = fs::read_dir(models_dir)?
        .filter_map(|entry| entry.ok().map(|value| value.path()))
        .filter(|path| {
            path.extension()
                .and_then(|extension| extension.to_str())
                .is_some_and(|extension| extension.eq_ignore_ascii_case("rbxm"))
        })
        .collect();
    paths.sort();

    let mut imported_count = 0;
    for path in paths {
        let template_id = path
            .file_stem()
            .and_then(|name| name.to_str())
            .ok_or_else(|| format!("invalid model filename: {}", path.display()))?;
        let model_dom = read_place(&path)?;
        let top_level_refs = model_dom.root().children().to_vec();
        if top_level_refs.is_empty() {
            return Err(format!("model contains no instances: {}", path.display()).into());
        }

        destroy_all_named_children(dest, baddies_parent, template_id);
        let imported_root = if top_level_refs.len() == 1 {
            clone_under(&model_dom, top_level_refs[0], dest, baddies_parent)
        } else {
            let wrapper = dest.insert(
                baddies_parent,
                InstanceBuilder::new("Model").with_name(template_id),
            );
            for source_ref in top_level_refs {
                clone_under(&model_dom, source_ref, dest, wrapper);
            }
            wrapper
        };

        if let Some(instance) = dest.get_by_ref_mut(imported_root) {
            instance.name = template_id.to_owned();
        }
        let imported_class = dest
            .get_by_ref(imported_root)
            .map(|instance| instance.class.to_string())
            .unwrap_or_else(|| "Unknown".to_owned());
        let removed_unsafe = remove_unsafe_instances_recursive(dest, imported_root);
        if removed_unsafe > 0 {
            println!(
                "Removed {} unsafe instance(s) from {}",
                removed_unsafe, template_id
            );
        }
        println!("Imported {} ({})", template_id, imported_class);
        imported_count += 1;
    }

    Ok(imported_count)
}

fn remove_unsafe_instances_recursive(dom: &mut WeakDom, root: Ref) -> usize {
    let children = match dom.get_by_ref(root) {
        Some(instance) => instance.children().to_vec(),
        None => return 0,
    };
    let mut removed = 0;

    for child_ref in children {
        let is_unsafe = dom
            .get_by_ref(child_ref)
            .is_some_and(|instance| is_unsafe_class(instance.class.as_str()));
        if is_unsafe {
            dom.destroy(child_ref);
            removed += 1;
        } else {
            removed += remove_unsafe_instances_recursive(dom, child_ref);
        }
    }

    removed
}

fn read_place(path: &Path) -> Result<WeakDom, Box<dyn Error>> {
    let file = File::open(path)?;
    Ok(rbx_binary::from_reader(BufReader::new(file))?)
}

fn write_place(path: &Path, dom: &WeakDom) -> Result<(), Box<dyn Error>> {
    let file = File::create(path)?;
    let mut writer = BufWriter::new(file);
    let top_level_refs = dom.root().children().to_vec();
    rbx_binary::to_writer(&mut writer, dom, &top_level_refs)?;
    writer.flush()?;
    Ok(())
}

fn sync_direct_children(
    source: &WeakDom,
    dest: &mut WeakDom,
    parent_path: &[&str],
    preserve_names: &[&str],
) -> Result<(), Box<dyn Error>> {
    let source_parent = find_path(source, parent_path)
        .ok_or_else(|| format!("source path not found: {}", parent_path.join("/")))?;
    let dest_parent = ensure_path_from_source(source, dest, parent_path)?;
    let children = source
        .get_by_ref(source_parent)
        .expect("source parent ref should exist")
        .children()
        .to_vec();

    for source_child_ref in children {
        let source_child = source
            .get_by_ref(source_child_ref)
            .expect("source child ref should exist");
        let name = source_child.name.as_str();

        if preserve_names.contains(&name) {
            continue;
        }

        destroy_all_named_children(dest, dest_parent, name);
        clone_under(source, source_child_ref, dest, dest_parent);
    }

    Ok(())
}

fn ensure_path_from_source(
    source: &WeakDom,
    dest: &mut WeakDom,
    path: &[&str],
) -> Result<Ref, Box<dyn Error>> {
    if path.is_empty() {
        return Ok(dest.root_ref());
    }

    if let Some(existing) = find_path(dest, path) {
        return Ok(existing);
    }

    let parent_ref = ensure_path_from_source(source, dest, &path[..path.len() - 1])?;
    let source_ref = find_path(source, path)
        .ok_or_else(|| format!("source path not found: {}", path.join("/")))?;

    Ok(clone_under(source, source_ref, dest, parent_ref))
}

fn clone_under(source: &WeakDom, source_ref: Ref, dest: &mut WeakDom, dest_parent: Ref) -> Ref {
    let cloned_ref = source.clone_into_external(source_ref, dest);
    dest.transfer_within(cloned_ref, dest_parent);
    cloned_ref
}

fn destroy_all_named_children(dom: &mut WeakDom, parent: Ref, name: &str) {
    while let Some(existing) = find_child(dom, parent, name) {
        dom.destroy(existing);
    }
}

fn find_path(dom: &WeakDom, path: &[&str]) -> Option<Ref> {
    let mut current = dom.root_ref();

    for segment in path {
        current = find_child(dom, current, segment)?;
    }

    Some(current)
}

fn find_child(dom: &WeakDom, parent: Ref, name: &str) -> Option<Ref> {
    let parent_instance = dom.get_by_ref(parent)?;

    for child_ref in parent_instance.children() {
        let child = dom.get_by_ref(*child_ref)?;
        if child.name == name {
            return Some(*child_ref);
        }
    }

    None
}

fn count_scripts(dom: &WeakDom) -> usize {
    dom.descendants()
        .filter(|instance| {
            matches!(
                instance.class.as_str(),
                "Script" | "LocalScript" | "ModuleScript"
            )
        })
        .count()
}

fn is_unsafe_class(class_name: &str) -> bool {
    matches!(
        class_name,
        "Script"
            | "LocalScript"
            | "ModuleScript"
            | "ProximityPrompt"
            | "ClickDetector"
            | "RemoteEvent"
            | "RemoteFunction"
            | "BindableEvent"
            | "BindableFunction"
            | "Sound"
    )
}

fn count_unsafe_below(dom: &WeakDom, root: Ref) -> usize {
    let Some(instance) = dom.get_by_ref(root) else {
        return 0;
    };

    instance
        .children()
        .iter()
        .map(|child_ref| {
            let Some(child) = dom.get_by_ref(*child_ref) else {
                return 0;
            };
            let is_unsafe = is_unsafe_class(child.class.as_str()) as usize;
            is_unsafe + count_unsafe_below(dom, *child_ref)
        })
        .sum()
}

#[cfg(test)]
mod tests {
    use super::is_unsafe_class;

    #[test]
    fn imported_interactive_or_executable_instances_are_unsafe() {
        for class_name in [
            "Script",
            "LocalScript",
            "ModuleScript",
            "ProximityPrompt",
            "ClickDetector",
            "RemoteEvent",
            "RemoteFunction",
            "BindableEvent",
            "BindableFunction",
            "Sound",
        ] {
            assert!(
                is_unsafe_class(class_name),
                "{class_name} should be removed"
            );
        }

        for class_name in ["Model", "MeshPart", "Part", "Attachment", "Decal"] {
            assert!(
                !is_unsafe_class(class_name),
                "{class_name} should remain in imported art"
            );
        }
    }
}
